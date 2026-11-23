#define APB_BRAM (0x10000000)
#define APB_PEPH (0x20000000)
#define APB_GPI  (APB_PEPH + 0x000u)
#define APB_GPO  (APB_PEPH + 0x100u)
#define APB_GPIO (APB_PEPH + 0x200u)

#define __IO volatile

typedef struct{
    __IO unsigned int CTR;
    __IO unsigned int IDR;
} GPI_typedef;

typedef struct{
    __IO unsigned int CTR;
    __IO unsigned int ODR;
} GPO_typedef;

typedef struct{
    __IO unsigned int CTR;
    __IO unsigned int IDR;
    __IO unsigned int ODR;
} GPIO_typedef;

#define GPI_A  ((GPI_typedef *)  APB_GPI)
#define GPO_B  ((GPO_typedef *)  APB_GPO)
#define GPIO_C ((GPIO_typedef *) APB_GPIO)


void GPIO_init(GPIO_typedef *GPIO, unsigned int control){
    GPIO -> CTR = control;
}

void GPIO_write(GPIO_typedef *GPIO, unsigned int wdata){
    GPIO -> ODR = wdata;
}

unsigned int GPIO_read(GPIO_typedef *GPIO){
    return GPIO -> IDR;
}

void delay(int n){
    unsigned int temp = 0;
    for(int i=0; i<n; i++){
        for(int j=0; j<256; j++)
        temp++;
    }
}

void main(void) {

    *(unsigned int *)   APB_BRAM = 0x12345678;

    int in_sw = 0;

    GPIO_init(GPIO_C, 0x000000ff);
    in_sw = GPIO_read(GPIO_C);

    GPIO_write(GPIO_C, in_sw);
    *(unsigned int *) 0x20000104 = 0x00000055;

    while(1){
        in_sw = GPIO_read(GPIO_C);
        GPIO_write(GPIO_C, in_sw);
        delay(10);
        GPIO_write(GPIO_C, (~in_sw));
        delay(10);
    }
}
