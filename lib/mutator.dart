import 'package:analyzer/analyzer.dart';
import 'package:analyzer/src/generated/ast.dart';
import './src/custom_resolver.dart';
import 'dart:async';
// deprecated, but StringToken class needs scanner.
import 'package:analyzer/src/generated/scanner.dart';

export 'package:analyzer/analyzer.dart';
export 'package:analyzer/src/generated/ast.dart';
export 'package:analyzer/src/generated/scanner.dart';

///Refactors code, see the example folder for usage examples.
class Mutator<T>{
  String klass_name;
  String pattern;
  RegExp expression_matcher;
  RegExp klass_matcher;
  Function replacer;
  List<String> included_packages;
  Resolver resolver; //set in mutator method
  DepResolver dr; //set in mutator method
  bool skip_type_check = false;
  String alias_name = null;

  /// Transformer does not always pass a library main first.
  /// When part files are passed to mutator before library main
  /// the execution has to wait till library main is passed to
  /// mutator.
  /// When the library main is processed, mutator checks if
  /// its parts are queued in completer_pool and if that is
  /// the case, completes them.
  ///
  ///     {absolute_file_path:[
  ///       (){ compute();completer.complete(result);}
  ///      ,...]}
  ///
  /// the method [mutate] calls, pops and adds to completer_pool.
  static Map<String, List<Function>> completer_pool = {};
  /// See the file mutator_example.dart
  /// in example folder for usage.
  ///
  ///Takes:
  /// +  class name.
  /// +  invocation pattern string.
  /// e.g. `'add_.*' `
  /// +  replacer function.
  /// e.g.
  ///
  ///     String replacer(AstNode e){
  ///         String s = e.toString();
  ///         List l  = s.split('=');
  ///         var invocation = l.removeAt(0).split('.');
  ///         String name = invocation.removeLast();
  ///         invocation = invocation.join('.') +
  ///             '.set(\'${name}\', ${l.join('=')})';
  ///         return invocation;
  ///       }
  ///
  /// Only nodes of type T that match the
  /// given pattern are modified.
  ///
  /// extractor can be provided at
  /// the invocation time of the mutate
  /// method, but mutate_t should be
  /// sufficient for most purposes.
  ///
  /// `required_import` option
  /// allows skipping running mutate on files
  /// that do not contain at least one of the
  /// packages.
  /// If not specified, no file is skipped.
  ///
  /// `alias_name`option should be set to modify
  /// a MethodInvocation of a function defined
  /// in an aliased file:
  /// e.g.
  ///
  ///       import 'dart:math' as math;
  ///       main(){ return math.max(5,7);}
  ///
   Mutator(
      this.klass_name,
      this.pattern,
      this.replacer,
      {List required_imports:const [],
      String alias_name:null
      }
  ){
      included_packages = required_imports;
      expression_matcher = new RegExp(pattern);
      klass_matcher = new RegExp(klass_name);
     this.alias_name = alias_name;
  }
  /// Use mutate_t unless you must write
  /// a custom extractor or filter.
  /// extractor takes a CompilationUnit
  /// and returns a list of all the
  /// nodes of the type T in the given
  /// CompilationUnit.
  /// todo test with the path set to an empty string.
  Future<String> mutate(
      String path,
      Function extractor,
      Function filter,
      [String code='' ]) async{
    DepResolver dr;
    if(code != ''){
      //todo need some caching solution, this is not working.
      dr = new DepResolver.from_string(path,code);
    }else{
      dr = new DepResolver(path);
    }
    // is the file is a part file and library main not loaded
    // wait the execution.
    if(dr.isPart()){
      if(dr.main == null){
        var c = new Completer();
        completer_pool[dr.absolute_path] ??= [];
        List p = completer_pool[dr.absolute_path];
        Function f(){
          String r = do_mutate(extractor,filter,dr);
          c.complete(r);
        };
        p.add(f);
        return c.future;
      }else{
        return do_mutate(extractor,filter,dr);
      }
    }else{
      //complete part files queue
      for(DepResolver d in dr.parts){
        if( completer_pool[d.absolute_path] != null){
          List l = completer_pool[d.absolute_path];
          for(int i = 0; i< l.length;++i){
            l[i].call();
          }
          l.clear();
        }
      }
      return do_mutate(extractor,filter,dr);
    }
  }
  String do_mutate(Function extractor, Function filter,DepResolver dr){
    // filtering by packages used,
    // if none specified, this check is
    // skipped.
    for(String req in included_packages){
      if(!dr.is_imported(req)) {
        return dr.ast.toSource(); //no modification
      }
    }
    var r = new Resolver<T>(dr);
    resolver = r;
    List nodes = extractor(dr.ast);
    nodes = filter(nodes);
    //nothing to modify found
    if(nodes == null){
      return dr.toSource();
    }
    //modifying
    for(AstNode e in nodes){
      String s = replacer(e);
      int pos = e.offset;
      var st = new StringToken(TokenType.STRING,s,pos);
      var ssl = new SimpleStringLiteral(st,s);
      e.parent.accept(new NodeReplacer(e,ssl));
    }
    return dr.toSource();
  }
  Future<String> mutate_t( String path,
      {String code : '',
      skip_type_check:false} ) async {
    this.skip_type_check = skip_type_check;
    List<T> node_extractor(CompilationUnit ast){
      List nodes = resolver.extract_type_T( ast);
      return nodes;
    }
    return mutate(
        path, node_extractor,default_filter,code);
  }
  List<AstNode> default_filter(List<AstNode> nodes){
    nodes.removeWhere( (e) =>
      !expression_matcher.hasMatch(e.toString()));
    nodes.removeWhere((n)=> !is_n_invoked_on(n) );
    return nodes;
  }
  /// Returns PropertyAccess, PrefixedIdentifier
  /// or null.
  ///
  /// Given the MethodInvocation node
  /// `A.b.c.hi()`, returns `A.b.c` which is
  /// a PropertyAccess node.
  ///
  ///  With `p.d.hi()`, returns
  /// `p.d` which is a PrefixedIdentifier.
  ///
  /// With `A.d.on(e).hi = 'bye'`, returns
  /// `A.d`.
  ///
  /// Originally extract_prefixed_identifier
  /// was used in the place of this method
  /// and resolver may depend on that method
  /// still.
  /// This method maybe moved into Resolver or
  /// removed in the future.
  ///
  ///
  /// todo support a pattern like:
  /// `A.d.on(e).hi.d.on(e).bye = 'bye'`
  /// and make this return `A.d.on(e).hi.d`.
  ///
  dynamic extract_invocation_base(AstNode n){
    var v = new GVisitor();
    n.visitChildren(v);
    List nodes = v.nodes;
    if(n is AssignmentExpression ||
        n is PropertyAccess ||
        n is MethodInvocation ||
        n is InstanceCreationExpression
    ){
      //Get propertyAccess or Prefixed identifier
      //that does not contain (.
      for(var node in nodes){
        if(
          (node is PrefixedIdentifier ||
              node is PropertyAccess
          ) && node.toString().indexOf('(') < 0
        ){
          return node;
        }
      }
    }

    // Invoked directly on an instance variable.
    // No prefix.
    for(var node in nodes){
      if(node is SimpleIdentifier)
        return node;
    }
    return null;
  }

  /// Checks if the node n is invoked on a class matching
  /// the klass_matcher.
  bool is_n_invoked_on(AstNode n){
    /// There is an issue with identifying the base.
    /// e.g. `c` in the case of `A.b.c.hi()`.
    /// `A.b.c` is a PropertyAccess.
    ///
    /// e.g. `d` in `p.d.hi()`
    /// `p.d` is a PrefixedIdentifier.
    ///
    /// extract_invocation_base is used to circumvent
    /// the problem, but the method is inefficient and
    /// ugly.
//    print('precessing $n');
//    show(n);
    if(skip_type_check) {
      if (alias_name == null) return true;

      // alias_name is set
      List ids = split_identifiers(
          extract_invocation_base(n));
      if(ids != null && ids.isNotEmpty){
        if(ids.first.toString() != alias_name)
          return false;
        if(ids.length == 1) return true;
        return true;
      }
      return false;
    }

    List ids = split_identifiers(
        extract_invocation_base(n));
    if(ids == null || ids.isEmpty) return false;

    TypeInfo type = resolver
        .get_right_most_identifier_type(
        ids,dr,dr);
//    print('right most identifier ${ids.last}\'s type for '
//        'the node $n is ${type?.type_name}');
    if(type == null) return false;

    if(alias_name != null) {
      //currently TypeInfo does not include alias used.
      //checking definition instead.
      var rv = extract_rvalue(type.definition);
      if (rv is AsExpression) {
        var l = as_expression_to_type_alias_pair(rv);
        if (l[1] != alias_name) return false;
        return true;
      }
      List alias_class_name = split_identifiers(rv);
      if (alias_class_name.length != 2) return false;

      //check if t is really an alias
      var t = resolver.get_type_info(alias_class_name.first);
      if (t.alias_name != alias_name) return false;
//      print('$n is invoked on the type ${type.type_name}');
    }
    return klass_matcher.hasMatch(type.type_name);
  }
}
