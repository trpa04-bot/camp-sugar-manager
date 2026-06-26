enum MrzType {
  td1,
  td2,
  td3,
  unknown;

  int get rowCount {
    switch (this) {
      case MrzType.td1:
        return 3;
      case MrzType.td2:
      case MrzType.td3:
        return 2;
      case MrzType.unknown:
        return 0;
    }
  }

  int get rowLength {
    switch (this) {
      case MrzType.td1:
        return 30;
      case MrzType.td2:
        return 36;
      case MrzType.td3:
        return 44;
      case MrzType.unknown:
        return 0;
    }
  }
}
