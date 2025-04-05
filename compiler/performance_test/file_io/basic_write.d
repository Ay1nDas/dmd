module dmd.compiler.performance_test.file_io.basic_write;

import std.stdio;
import std.file;

void main(){
  File file = File("test.txt", "w"); // Open file (system call)
  file.close(); // Close file (system call)
}