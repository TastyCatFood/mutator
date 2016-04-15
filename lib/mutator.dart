import 'package:analyzer/analyzer.dart';
import 'package:analyzer/src/generated/ast.dart';
import './src/custom_resolver.dart';
// deprecated, but StringToken class needs scanner.
import 'package:analyzer/src/generated/scanner.dart';

export 'package:analyzer/analyzer.dart';
export 'package:analyzer/src/generated/ast.dart';
export 'package:analyzer/src/generated/scanner.dart';

///Modifies code
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
  /// See the file mutator_example.dart
  /// in example folder.
  ///
  ///Takes:
  /// +  class name.
  /// +  invocation pattern string.
  /// e.g. `'add_.*' `
  /// +  replacer function.
  /// e.g.
  ///
  ///     (e){
  ///         String s = e.toString();
  ///         List l  = s.split('=');
  ///         var invocation = l.removeAt(0).split('.');
  ///         String name = invocation.removeLast();
  ///         invocation = invocation.join('.') +
  ///             '.set(\'${name}\', ${l.join('=')})';
  ///         return invocation;
  ///
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
  /// required_import
  /// allows skipping running mutate on files
  /// that do not contain at least one of the
  /// packages.
  /// If not specified, no file is skipped.
  ///
  /// alias_name should be set to modify
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
  String mutate(
      String path,
      Function extractor,
      Function filter,
      [String code='' ]) {
    DepResolver dr;
    if(code != ''){
      //todo need some caching solution, this is not working.
      dr = new DepResolver.from_string(path,code);
    }else{
      dr ??= new DepResolver(path);
    }
    // filtering by packages used,
    // if none specified, this check is
    // skipped.
    for(String req in included_packages)
      if(!dr.is_imported(req))
        return dr.ast.toSource();//no modification

    var r = new Resolver<T>(dr);
    resolver = r;
    List nodes = extractor(dr.ast);
    nodes = filter(nodes);
    //nothing to modify found

    if(nodes == null) return dr.toSource();
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
  String mutate_t( String path,
      {String code : '',
      skip_type_check:false}
      ) {
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

  /// Checks if n is invoked on the class matching
  /// the klass_matcher.
  ///
  /// There is an issue with identifying the base.
  /// e.g. `c` in the case of `A.b.c.hi()`.
  /// `A.b.c` is a PropertyAccess.
  ///
  /// e.g. `d` in `p.d.hi()`
  /// `p.d` is a PrefixedIdentifier.
  ///
  ///
  bool is_n_invoked_on(AstNode n){
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
    }else{
      List ids = split_identifiers(
          extract_invocation_base(n));
      if(ids != null && ids.isNotEmpty){
        TypeInfo type = resolver
            .get_right_most_identifier_type(
            ids,dr,dr);
//      print('right most identifier ${ids.last}\'s type for '
//          'the node $n is ${type?.type_name}');
        if(type == null) return false;
        if(alias_name != null){
          //function call on an alias
          //e.g. `math.max(5,9)`
          if(type.alias_name != null){
            if(ids.first.toString() != alias_name)
              return false;
          }
          //checking if class name is prefixed
          // by the value of alias_name.
          //e.g. `new math.Random(5)` and not new random(5);
          var cn = extract_rvalue(type.definition);
          if(cn is! ConstructorName)
            return false;

          List alias_class_name = split_identifiers(cn);
          if(alias_class_name.length != 2) return false;
          var t = resolver.get_type_info(alias_class_name.first);
          if(t.alias_name != alias_name) return false;
        }
//      print('$n is invoked on the type ${type.type_name}');
        return klass_matcher.hasMatch(type.type_name);
      }
      // No property access, no prefix.
      // A function call or an access to a top
      // level variable without an alias.
      // skip_type_check should be set to true.
      return false;
    }
    throw 'this should not be called';
    return false;
  }
}
