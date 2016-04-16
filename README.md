# mutator
A dart language helper tool for pre-compile/transform time refactoring.
A potential alternative for Macro or inline function in desperate times.

##Status: Alpha
Type detection currently relies on a solution I improvised without
a proper design or abstraction and it is neither fast or exhaustively
tested.
Skip type detection by passing `skip_type_check:true`
to mutate_t method for safety and speed if possible;see usage
example1 for more details.


## Usage

A simple usage example:
Refactoring `math.max(5,9)` into `(){int t = 5;t = t<9?9:t;return t;}();`.

    import 'package:mutator/mutator.dart';
    String alias = 'math';
    String pattern = 'math\\.max\\([0-9,\\w\\s_]+\\)';
    //path needs to be set properly if there are relative file imports or part files.
    String file_path = '';//leaving empty as neither is the case.

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
    main(){
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
        s = s.substring(9,s.length-1);//removing `math.max(` and `)`
        var l = s.split(',');

        List f = ['(){int t = ${l[0]};'];

        for(String v in l.sublist(1))
          f.add(generate_code_for_getting_larger('t','t',v));

        f.add('return t;}()');
        return f.join();
      }
      var m = new Mutator<MethodInvocation>(
          '', pattern, replacer,alias_name: alias);
      print(m.mutate_t(file_path,code:src,skip_type_check:true));
    }


Refactoring `r.nextInt(5)` into a random number. Leaving
`r2.nextInt(5)` unchanged as r2 is not an instance of math.Random.


    import 'dart:math' as math;
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
    main(){
      int random_num;
      var r = new math.Random(5);
      replacer(MethodInvocation e){
        String s = e.toString();
        random_num = r.nextInt( int.parse(new RegExp('[0-9]+')
            .firstMatch(s).group(0)));
        return random_num.toString();
      }
      var m = new Mutator<MethodInvocation>(
          klass_name, pattern, replacer,alias_name: 'math');
      print(m.mutate_t(path,code:src));
    }

Refactoring `d.on(o).hi = ()=>print('hi');` into `d.on(o).set('hi',()=>print('hi'));`

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
    main(){
        replacer(e){
            String s = e.toString();
            List l  = s.split('=');
            var invocation = l.removeAt(0).split('.');
            String name = invocation.removeLast().trim();
            invocation = invocation.join('.') +
                '.set(\'${name}\', ${l.join('=').trim()})';
            return invocation;
        }
        var m = new Mutator<AssignmentExpression>(
          klass_name, pattern, replacer);
        print(m.mutate_t(file_path,code:code));
    }
## Features and bugs
Please file feature requests and bugs at the  https://github.com/TastyCatFood/mutator/issues.

## Limitations
+ No type detection available when the type is not statically defined.
e.g.

        f(e){ return e.nextInt(4);}


+  Function's return type is ignored.
e.g.

        math.Random f(){new math.Random(501);}
        main(){
            f().nextInt(7);
        }

+ Type information within conditional statement are ignored.
e.g.

        f(e){
           if(e is math.Random){
            return e.nextInt(2);
           }
        }

#### Does not detect the type of variables defined in a file that has been imported as a package or a part of dart-sdk.
e.g.

        import 'package:example_code.dart' as eg;
        main(){
        // Mutator does not look into the package to find the type of [a].
            print(eg.a);
        }

The type of [a] is available when `example_code.dart` is imported relatively; `import './example_code.dart';` or as a part file.

