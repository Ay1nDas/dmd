module dmd.compiler.performance_test.simple_codes.bare_hello;

extern(C) void main() {
    import core.stdc.stdio;
    printf("Hello from bare metal!\n");
}