module dmd.compiler.performance_test.max_ram.optimed_ram;

// The following code should use minimal memory, as the variables are not used.

void main(){

  bool[10_000_000] arr2;
  char[10_000_000] arr3;
  int[10_000_000] arr1;
  float[10_000_000] arr5;
  double[10_000_000] arr4;
  long[10_000_000] arr6;
  short[10_000_000] arr7;
  ifloat[10_000_000] arr8;
  idouble[10_000_000] arr9;
  ulong[10_000_000] arr10;
  ushort[10_000_000] arr11;
  wchar[10_000_000] arr12;
  dchar[10_000_000] arr13;
  real[10_000_000] arr14;
  ireal[10_000_000] arr15;
  creal[10_000_000] arr78;

  immutable int[10_000_000] arr16;
  immutable bool[10_000_000] arr17;
  immutable char[10_000_000] arr18;
  immutable double[10_000_000] arr19;
  immutable float[10_000_000] arr20;
  immutable long[10_000_000] arr21;
  immutable short[10_000_000] arr22;
  immutable ifloat[10_000_000] arr23;
  immutable idouble[10_000_000] arr24;
  immutable ulong[10_000_000] arr25;
  immutable ushort[10_000_000] arr26;
  immutable wchar[10_000_000] arr27;
  immutable dchar[10_000_000] arr28;
  immutable real[10_000_000] arr29;
  immutable ireal[10_000_000] arr30;

  const int[10_000_000] arr31;
  const bool[10_000_000] arr32;
  const char[10_000_000] arr33;
  const double[10_000_000] arr34;
  const float[10_000_000] arr35;
  const long[10_000_000] arr36;
  const short[10_000_000] arr37;
  const ifloat[10_000_000] arr38;
  const idouble[10_000_000] arr39;
  const ulong[10_000_000] arr40;
  const ushort[10_000_000] arr41;
  const wchar[10_000_000] arr42;
  const dchar[10_000_000] arr43;
  const real[10_000_000] arr44;
  const ireal[10_000_000] arr45;

  immutable const int[10_000_000] arr46;
  immutable const bool[10_000_000] arr47;
  immutable const char[10_000_000] arr48;
  immutable const double[10_000_000] arr49;
  immutable const float[10_000_000] arr50;
  immutable const long[10_000_000] arr51;
  immutable const short[10_000_000] arr52;
  immutable const ifloat[10_000_000] arr53;
  immutable const idouble[10_000_000] arr54;
  immutable const ulong[10_000_000] arr55;
  immutable const ushort[10_000_000] arr56;
  immutable const wchar[10_000_000] arr57;
  immutable const dchar[10_000_000] arr58;
  immutable const real[10_000_000] arr59;
  immutable const ireal[10_000_000] arr60;
  
  const immutable int[10_000_000] arr61;
  const immutable bool[10_000_000] arr62;
  const immutable char[10_000_000] arr63;
  const immutable double[10_000_000] arr64;
  const immutable float[10_000_000] arr65;
  const immutable long[10_000_000] arr66;
  const immutable short[10_000_000] arr67;
  const immutable ifloat[10_000_000] arr68;
  const immutable idouble[10_000_000] arr69;
  const immutable ulong[10_000_000] arr70;
  const immutable ushort[10_000_000] arr71;
  const immutable wchar[10_000_000] arr72;
  const immutable dchar[10_000_000] arr73;
  const immutable real[10_000_000] arr74;
  const immutable ireal[10_000_000] arr75;

  int* ptr1;
  char* ptr2;
  float* ptr3;
  double* ptr4;
  long* ptr5;
  short* ptr6;
  ifloat* ptr7;
  idouble* ptr8;
  ulong* ptr9;
  ushort* ptr10;
  wchar* ptr11;
  dchar* ptr12;
  real* ptr13;
  ireal* ptr14;

  int ** ptr_ptr;
}