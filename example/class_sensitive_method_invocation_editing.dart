import 'dart:math' as math;
import 'dart:async';
import 'package:mutator/mutator.dart';

String pattern = '[\\w0-9_]+\\.nextInt\\([0-9]+\\)';
String klass_name = 'Random';
String path = '';//dummy path
String src = """
    import 'dart:math' as math;
    main(){
    var r = new math.Random(5);
    print(r.nextInt(600));
    var r2 = new Random();
    print(r2.nextInt(600));
    }
    class Random{
        nextInt(int n){
          return n +5;
        }
    }
    """;
/// main should transform the value of src into
/// the code below and print it:
///
///import 'dart:math' as math;
///
///main() {
///  var r = new math.Random(5);
///  print(88);//Changed
///  var r2 = new Random();
///  print(r2.nextInt(600));//Not changed
///}
///
///class Random {
///  nextInt(int n) {
///    return n + 5;
///  }
///}
///
main() async{
  int random_num;
  var r = new math.Random(5);
  replacer(MethodInvocation e){
    String s = e.toString();
    random_num = r.nextInt( int.parse(new RegExp('[0-9]+')
        .firstMatch(s).group(0)));
    return random_num.toString();
  }
  var m = await new Mutator<MethodInvocation>(
      klass_name, pattern, replacer,alias_name: 'math');
  print(await m.mutate_t(path,code:src));
}