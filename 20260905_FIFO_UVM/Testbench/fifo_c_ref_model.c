#include <stdint.h>

#define FIFO_C_REF_DEFAULT_DEPTH 4
#define FIFO_C_REF_MAX_DEPTH     1024

static uint8_t fifo_mem[FIFO_C_REF_MAX_DEPTH];
static int fifo_depth = FIFO_C_REF_DEFAULT_DEPTH;
static int fifo_wr_ptr = 0;
static int fifo_rd_ptr = 0;
static int fifo_count = 0;

static void fifo_c_ref_reset_state(void)
{
    fifo_wr_ptr = 0;
    fifo_rd_ptr = 0;
    fifo_count = 0;
}

void fifo_c_ref_init(int depth)
{
    if ((depth > 0) && (depth <= FIFO_C_REF_MAX_DEPTH)) {
        fifo_depth = depth;
    } else {
        fifo_depth = FIFO_C_REF_DEFAULT_DEPTH;
    }

    fifo_c_ref_reset_state();
}

int fifo_c_ref_step(
    int rst,
    int push,
    int pop,
    int wr_data,
    int *exp_pre_full,
    int *exp_pre_empty,
    int *exp_pop_valid,
    int *exp_rd_data,
    int *exp_post_full,
    int *exp_post_empty,
    int *exp_size
)
{
    int is_full;
    int is_empty;
    int eff_push = 0;
    int eff_pop = 0;

    if ((exp_pre_full == 0) || (exp_pre_empty == 0) ||
        (exp_pop_valid == 0) || (exp_rd_data == 0) ||
        (exp_post_full == 0) || (exp_post_empty == 0) ||
        (exp_size == 0)) {
        return 0;
    }

    is_full = (fifo_count == fifo_depth);
    is_empty = (fifo_count == 0);

    *exp_pre_full = is_full;
    *exp_pre_empty = is_empty;
    *exp_pop_valid = 0;
    *exp_rd_data = 0;

    if (rst) {
        fifo_c_ref_reset_state();

        *exp_post_full = 0;
        *exp_post_empty = 1;
        *exp_size = fifo_count;
        return 1;
    }

    if (push && !pop && !is_full) {
        eff_push = 1;
    } else if (!push && pop && !is_empty) {
        eff_pop = 1;
    } else if (push && pop) {
        if (is_empty) {
            eff_push = 1;
        } else if (is_full) {
            eff_pop = 1;
        } else {
            eff_push = 1;
            eff_pop = 1;
        }
    }

    if (eff_pop) {
        *exp_pop_valid = 1;
        *exp_rd_data = fifo_mem[fifo_rd_ptr];
        fifo_rd_ptr = (fifo_rd_ptr + 1) % fifo_depth;
        fifo_count--;
    }

    if (eff_push) {
        fifo_mem[fifo_wr_ptr] = (uint8_t)(wr_data & 0xff);
        fifo_wr_ptr = (fifo_wr_ptr + 1) % fifo_depth;
        fifo_count++;
    }

    *exp_post_full = (fifo_count == fifo_depth);
    *exp_post_empty = (fifo_count == 0);
    *exp_size = fifo_count;

    return 1;
}
