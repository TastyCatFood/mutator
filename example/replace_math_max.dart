import 'package:mutator/mutator.dart';
import 'dart:async';

String alias = 'math';
String pattern = 'math\\.max\\([0-9,\\w\\s_]+\\)';
String file_path = '';//dummy path.
String src = """
      import 'dart:math' as math;
      main(){
        int m = math.max(5,94,8,3,5,7,4);
      }
      """;

///main  should transform the value of
///src into the code below.
///
///   import 'dart:math' as math;
///   main() {
///     int m = () {
///       int t = 5;
///       t = t < 94 ? 94 : t;
///       t = t < 8 ? 8 : t;
///       t = t < 3 ? 3 : t;
///       t = t < 5 ? 5 : t;
///       t = t < 7 ? 7 : t;
///       t = t < 4 ? 4 : t;
///       return t;
///     }();
///}
main() async{
  replacer(MethodInvocation e){
    String generate_code_for_getting_larger(
        String variable_name,
        String value1,
        String value2){
      return '${variable_name} = '
          '${value1.trim()}<${value2.trim()}?'
          '${value2.trim()}:${value1.trim()};';
    }
    String s = e.toString();
    s = s.substring(9,s.length-1);//removing math.max(
    var l = s.split(',');

    //creating a temporary function
    List f = ['(){int t = ${l[0]};'];

    for(String v in l.sublist(1))
      f.add(generate_code_for_getting_larger('t','t',v));

    //closing the function
    f.add('return t;}()');
    return f.join();
  }
  var m = await new Mutator<MethodInvocation>(
      '', pattern, replacer,alias_name: alias);
  print(await m.mutate_t(file_path,code:src,skip_type_check:true));
}
