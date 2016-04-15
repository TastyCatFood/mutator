import 'package:mutator/mutator.dart';
String code = """
    import 'package:mistletoe';
    var d = new Dynamism(expert:true);
    main(){
        var o = new Object();
        d.on(o).hi = ()=>print('hi');
    }
    """;
const String klass_name = 'Dynamism';
const String pattern =
    '^[a-z.A-Z_0-9]+\\.on\\'
    '([a-z.A-Z_0-9]+\\)\\.[a-z.A-Z_0-9]+';
String file_path = '';
main() {
  replacer(e) {
    String s = e.toString();
    List l = s.split('=');
    var invocation = l.removeAt(0).split('.');
    String name = invocation.removeLast().trim();
    invocation = invocation.join('.') +
        '.set(\'${name}\', ${l.join('=').trim()})';
    return invocation;
  }
  var m = new Mutator<AssignmentExpression>(
      klass_name, pattern, replacer);
  print(m.mutate_t(file_path, code: code));
}