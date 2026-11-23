void main(void) {
    *(unsigned int *)   0x10000000 = 0x12345678;

    int sw = 0;

    * (unsigned int *)  0x20000000 = 0x000000ff;
    * (unsigned int *)  0x20000100 = 0x000000ff;

    while(1){
        sw = *(unsigned int *) 0x20000004;
        *(unsigned int *)   0x20000104 = 0x00000055;
    }
}
