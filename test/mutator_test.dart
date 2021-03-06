import 'package:mutator/mutator.dart';
import 'package:path/path.dart' as Path;
import 'dart:io' show Platform, Directory;
import 'package:test/test.dart';
import 'dart:math' as math;


void main() {
  group('A group of tests', () {
    instance_creation_test();
    alias_test();
    aliased_type_detection_test();
    as_expression_with_alias_test();
  });
}
/// only modifies an MethodInvocation
/// on the instances of class Random that
/// are instantiated with the alias math
/// in InstanceCreationExpression.
/// e.g.
///
///     var r = new math.Random(5);
///
/// and not `var r2 = new Random(5);`
aliased_type_detection_test(){
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
  int random_num;
  var r = new math.Random(5);
  extractor(MethodInvocation e){
    //replace r.nextInt(600) with a number.
    //e should be of type math.Random and
    // not Random.
    String s = e.toString();
    random_num = r.nextInt(
        int.parse(new RegExp('[0-9]+')
            .firstMatch(s).group(0))
    );
    return random_num.toString();
  }
  var m = new Mutator<MethodInvocation>(
      klass_name, pattern, extractor,alias_name: 'math');
  test('alias and type detection test', ()async{
    expect(await m.mutate_t(path,code:src),
    "import 'dart:math' as math; "
    "main() {"
        "var r = new math.Random(5); "
        "print(${random_num}); "
        "var r2 = new Random(); "
        "print(r2.nextInt(600));} "
    "class Random {nextInt(int n) {return n + 5;}}"
    );
  });
}
alias_test(){
  String alias = 'math';
  String pattern = 'math\\.max\\([0-9,\\w\\s_]+\\)';
  String path = '';//dummy path.
  String src = """
  import 'dart:math' as math;
  main(){
    int m = math.max(5,9);
    print(m);
  }
  """;
  extractor(MethodInvocation e){
    String s = e.toString();
    s = s.substring(9,s.length-1);
    var l = s.split(',');
    if(l.length != 2) return e.toString();
    String r = '${l[0].trim()}<${l[1].trim()}?'
        '${l[1].trim()}:${l[0].trim()}';
    return r;
  }
  var m = new Mutator<MethodInvocation>(
      '', pattern, extractor,alias_name: alias);
  test('alias test', ()async{
  expect(await m.mutate_t(path,code:src,skip_type_check:true),
  "import 'dart:math' as math; "
      "main() {int m = 5<9?9:5; print(m);}");
  });
}
as_expression_with_alias_test(){
  String path = append_to_project_dir(
      '/test/mutator_targets/'
      'mutator_as_expression_'
          'with_alias_test_target.dart');
  String klass_name = 'B';
  String pattern = '[\\w_0-9]+\\.on\\([\\w_0-9_]\\)\\.[\\w_0-9]';
  String extraction_result;
  String replacer(AstNode n){
    extraction_result = n.toString();
    return extraction_result;
  }
  test('type detction test: class definition in an '
      'aliased import.',()async{
    var m = new Mutator<AssignmentExpression>(
        klass_name ,pattern , replacer ,alias_name: 'imp' );
    await m.mutate_t(path);
    expect(extraction_result,'e.on(t).greetings = \'hi\'');
  });
  test('type detction test: alias_name option '
      'set.',
      ()async{
    var m = new Mutator<AssignmentExpression>(
        klass_name ,pattern , replacer );
    await m.mutate_t(path);
    expect(extraction_result,'e.on(t).greetings = \'hi\'');
  });
  test('type detction test: alias_name set to a wrong name',
      ()async{
    extraction_result = '';
    var m = new Mutator<AssignmentExpression>(
        klass_name ,pattern , replacer,alias_name: 'im' );
    await m.mutate_t(path);
    expect(extraction_result,'');
  });
}
instance_creation_test(){
    String klass_name = 'RegExp';
    String pattern = '\\.hasMatch\\(\'[\\w_0-9]+\'\\)';
    String src = """
    import 'dart:math' as math;
    main(){
      if((new RegExp('hi')).hasMatch('hi')){
        print('yeap');
      }
    }
    """;
    replacer(e){
      return 'true';
    }
    var m =  new Mutator<MethodInvocation>(
        klass_name, pattern, replacer);
    test('dummy',()async{
      var r = await m.mutate_t('',code: src);
      expect(r,
          "import 'dart:math' as math; "
              "main() {if (true) {print('yeap');}}"
      );
    });
}

/// path must not contain `/` at the head position.
append_to_project_dir(String path,[base_dir = null]){
  if(path.indexOf('/') == 0)
    path = path.substring(1);
// To fetch the project home dir
//  var cd = Path.current;

//  To Change the current directory
//  Directory original_dir = Directory.current;
//  Directory.current = dirname.toFilePath();
  Path.Context context;
  if(Platform.isWindows){
    context = new Path.Context(style:Path.Style.windows);
  }else{
    context = new Path.Context(style:Path.Style.posix);
  }
  base_dir ??= Directory.current.path;
  path = context.join(
      Path.normalize(base_dir),
      Path.normalize(path));
  return context.normalize(path);
}
