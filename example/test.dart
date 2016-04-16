import 'dart:math' as math;

main() {
  var r = new math.Random(5);
  print(88);
  var r2 = new Random();
  print(r2.nextInt(600));
}

class Random {
  nextInt(int n) {
    return n + 5;
  }
}
