import 'package:analyzer/analyzer.dart';
import 'package:analyzer/src/generated/ast.dart';
import 'package:mutator/mutator.dart';
import 'package:path/path.dart' as Path;
import 'dart:io' show Platform;

const String klass_name = 'Dynamism';
const String pattern =
    '^[a-z.A-Z_0-9]+\\.on\\'
    '([a-z.A-Z_0-9]+\\)\\.[a-z.A-Z_0-9]+';
String file_path = to_abs_path('../web/index.dart');
to_abs_path(path,[base_dir = null]){
// Fetching the project home dir
//  var cd = Path.current;

//  Changing the current directory
//  Directory original_dir = Directory.current;
//  Directory.current = dirname.toFilePath();
  Path.Context context;
  if(Platform.isWindows){
    context = new Path.Context(style:Path.Style.windows);
  }else{
    context = new Path.Context(style:Path.Style.posix);
  }
  base_dir ??= Path.dirname(
      Platform.script.toFilePath());
  path = context.join( base_dir,path);
  return context.normalize(path);
}
main() async {

  var m = new Mutator<AssignmentExpression>(
      klass_name, pattern,(e){
    String s = e.toString();
    List l  = s.split('=');
    var invocation = l.removeAt(0).split('.');
    String name = invocation.removeLast().trim();
    invocation = invocation.join('.') +
        '.set(\'${name}\', ${l.join('=').trim()})';
    return invocation;
  });
  String r = await m.mutate_t(file_path);


  m = new Mutator<PropertyAccess>(klass_name,pattern,
        (e){
      List l = e.toString().split('.');
      String property_name = l.removeLast();
      String invocation = l.join('.');
      invocation = invocation +
          '.get(\'${property_name.trim()}\')';
      return invocation;
    });
  r = await m.mutate_t(file_path,code:r);


  m = new Mutator<MethodInvocation>(klass_name,pattern,
      (MethodInvocation e){
          String s = e.toString();
          var m = new RegExp(
              'on\\([\\w_\\.]+\\)\\.').firstMatch(s);
          //splitting d.on(e).hi(e) into `d.on(e)`
          // and `hi(e)`
          String on_call = s.substring(0,m.end-1);
          String method_call = s.substring(m.end,s.length);

          //splitting `hi(e)` into `hi` and `(e)`
          int idx = method_call.indexOf('(');
          String method_name =
          method_call.substring(0,idx).trim();
          String params = method_call.substring(idx+1,
              method_call.length-1);
          //assembling parts into a method call
          return '${on_call}.invoke'
              '(\'${method_name}\',[${params}])';
  });
  r = await m.mutate_t(file_path,code:r);
  print(r);
  return;
}
