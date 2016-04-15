library custom_resolver;
import 'package:path/path.dart' as Path;
import 'package:analyzer/analyzer.dart';
import 'dart:io' show Platform;
//although deprecated, StringToken class requires this
import 'package:analyzer/src/generated/scanner.dart';

part './parts_resolver.dart';
part './custom_resolver_functions.dart';
/// Resolver takes PatsResolver to deal
/// with the cases where definitions are
/// in part file.
///
class Resolver<T> {
  DepResolver _pr;

  Resolver(this._pr) {}

  /// Takes class name identifier, a
  /// variable identifier, alias.
  ///
  /// Returns the most likely guess on the
  /// type of the given node.
  ///
  /// Sets different fields of TypeInfo
  /// depending to the type of the given
  /// node.
  ///
  /// Case: alias
  /// Sets alias_name and sets type_source
  /// to the file the alias points to.
  /// type_declaration is set to the file's
  /// ast.
  ///
  /// Case: class name
  /// Sets type_declaration, type_name and
  /// type_source.
  ///
  /// Case: variable identifier
  /// Sets type_name, definition,
  /// definition source, query_node,
  /// query_source.
  ///
  /// When shallow_search is set to true,
  /// searches only the top level of
  /// the file.
  ///
  /// When the search scope is given, searches
  /// only the top level of the scope.
  TypeInfo get_type_info(SimpleIdentifier node,
      {DepResolver search_target: null,
      DepResolver query_source:null,
      AstNode search_scope:null,
      bool shallow_search:false}) {
    //note:
    // An import alias could hide variable name
    // in a part file.
    search_target ??= _pr;
    query_source ??= _pr;
    var tf = new TypeInfo();
    tf.query_source = query_source;
    tf.query_node = node;
    tf.definition_source = search_target;


    // Handling the case where the node is a class name
    // identifier defined in the current file.
    // A ClassDeclaration in part file may be hidden
    // by an import alias, so search part files
    TypeInfo info = get_class_declaration_of(
        node.toString(),
        search_target: search_target
    );
    if (info != null) {
      //depth is not set
      tf.definition = info.type_declaration;
      tf.type_name = node.toString();
      tf.type_declaration = info.type_declaration;
      tf.type_source = info.type_source;
      return tf;
    }
    // Handling the case where node is a
    // class name in an InstanceCreationExpression.
    var t = new UpwardSearch<
        ConstructorName>(node).result;
    if(t != null && t.toString() == node.toString()){
      tf.type_name = node.toString();
      tf.definition_depth_from_query = 0;
      return tf;
    }

    //node is not a class name identifier.
    //Assuming node is a variable identifier now.
    List definitions =
      guess_effective_definition_of(
          node,search_target,query_source,
          search_scope: search_scope,
          shallow_search:shallow_search);
    if(definitions == null) return null;
    TypeInfo g = definitions.first;
    if(g == null) return null;
    // node could be an import alias.
    // currently packages and dart-sdk lib
    // are not supported, so type_source could be null.
    if (g.alias_name != null) {
        tf.type_source =
            search_target.get_dep_resolver(g.alias_name);
        tf.alias_name = node.toString();
        tf.type_declaration = tf.definition_source.ast;
        return tf;
    }
    // The most likely guess, maybe d of Dynamism d;
    tf.definition = g.definition;

    _handle_declaration(VariableDeclaration d){
      TypeInfo t = declaration_to_type_info(
          d,search_target,query_source);
      if(t == null) return null;
      tf.type_name = t.type_name;
      tf.definition_source =
          t.definition_source;
      tf.definition_depth_from_query =
          t.definition_depth_from_query;
      return tf;
    }
    _handle_formal_parameter(FormalParameter p){
      var type;
      String type_name;
      if (p.childEntities.length > 1) {
        type = _extract_TypeName_from(p);
      }
      if(type == null) return null;
      tf.type_name = type_name;
      return tf;
    }
    _handle_assignment_expression(AssignmentExpression a){
      var rv = extract_rvalue(a);
      TypeInfo t = rvalue_to_type_info(
          rv,search_target,query_source);
      tf..definition_depth_from_query =
          t.definition_depth_from_query
        ..definition = t.definition
        ..definition_source = t.definition_source
        ..type_name = t.type_name;
      return tf;
    }

    if (g.definition is VariableDeclaration) {
      return _handle_declaration(g.definition);
    }
    if (g.definition is AssignmentExpression) {
      // Checking if the type is statically
      // defined in in FormalParameter or
      // VariableDeclaration./
      if(definitions.length > 1){
        var second = definitions[1].definition;

        if(second is FormalParameter){
          var r = _handle_formal_parameter(second);
          if(r != null) return r;
        }
        if(second is VariableDeclaration){
          var r = _handle_declaration(second);
          if(r != null) return r;
        }
      }
      return _handle_assignment_expression(g.definition);
    }

    if (g.definition is FormalParameter) {
      return _handle_formal_parameter(g.definition);
    }
    return throw 'unknown type ${g.runtimeType} '
        'value: ${g.definition}';
  }

  ///Takes either simple identifier or String
  TypeInfo get_alias_match(
      n,{DepResolver search_target:null}){
    search_target ??= _pr;
    String identifier = n.toString();
    int depth = 0;
    while(n != null){
      n = get_surrounding_block(n);
      depth -= 1;
    }
    for(var pair in search_target.imported_alias_pairs){
      if(pair[1] == '') continue;
      if(identifier == pair[1]){
        var ti = new TypeInfo()
            ..alias_name = identifier
            ..query_source = n
            ..definition_depth_from_query = depth
            ..definition_source = pair[0]
            ..definition = pair[0]?.ast;
        return ti;
      }
    }
    return null;
  }
  TypeInfo constructor_name_to_type_info(
      cn,
      DepResolver search_target,
      DepResolver query_source){
    //todo find a way to distinguish prefixed
    // class name and an instance creation by a named
    // ConstructorInvocation.
    var r = new TypeInfo();
    r.definition_source = search_target;
    r.query_source = query_source;
    r.query_node = cn;

    String prefixed_id = cn.toString();
    List l = prefixed_id.split('.');
    if (prefixed_id.indexOf('.') > -1) {
      r.definition_source =
          search_target.get_dep_resolver(l[1]);
      r.type_name = l[1];
    }else{
      r.type_name = l[0];
    }
    return r;
  }

  /// Returns [type_name, alias], [type_name,null] or null
  /// if no alias, the second element is null.
  /// The declaration must be in the
  /// local library represented by _pr.
  ///
  /// sets only definition_source,
  /// query_source, type_name.
  ///
  /// The declaration part of `Dynamism d;` is
  /// only `d`.
  TypeInfo declaration_to_type_info(
      VariableDeclaration d,
      DepResolver search_target,
      DepResolver query_source) {
    TypeInfo t = new TypeInfo();
    t..definition_source = search_target
      ..query_source = query_source;
    // declaration does not include TypeName.
    // need parent.
    var type = _extract_TypeName_from(d.parent);
    if(type != null){
      t.type_name = type.toString();
      return t;
    }
    //check for as expression
    for (var e in d.childEntities) {
      if (e is AsExpression) {
        t.type_name = e.childEntities
            .last.toString;
        return t;
      }
    }

    //no static type info available
    var rv = extract_rvalue(d);
    return rvalue_to_type_info(
        rv, search_target,query_source);
  }
  /// Only sets the query_source,
  /// definition_source and type_name
  /// fields of TypeInfo object.
  TypeInfo rvalue_to_type_info(
      AstNode rv,
      DepResolver search_target,
      DepResolver query_source){
    if(rv == null) return null;
    TypeInfo t = new TypeInfo()
      ..query_source = query_source
      ..definition_source = search_target;


    if (rv is Literal) {
      String type_name = rv.runtimeType.toString();
      t.type_name = type_name.replaceAll('Simple', '')
          .replaceAll('Literal', '');
      return t;
    }
    if(rv is InstanceCreationExpression){
      rv = rv.childEntities.toList()[1];
    }
    if (rv is ConstructorName) {
      TypeInfo ti = constructor_name_to_type_info(
          rv,search_target,query_source);
      if(ti == null) return null;
      t.definition_source = ti.definition_source;
      t.definition = ti.definition;
      t.type_name = ti.type_name;
      return t;
    }

    if (rv is AsExpression) {
      var l = _as_expression_to_type_alias_pair(rv);
      if(l == null) return null;
      if(l[1] != null)
        t.definition_source =
            search_target.get_dep_resolver(l[1]);
      t.type_name= l[0];
      return t;
    }
    //variable
    if(rv is Identifier) {
      var t = get_type_info(
          rv, search_target: search_target,
          query_source:query_source,
          shallow_search:
            query_source != search_target
      );
      if (t == null) return null;
      return t;
    }
    if(rv is PrefixedIdentifier){
      var ids = split_identifiers(rv);
      TypeInfo t = get_right_most_identifier_type(
          ids,search_target,query_source);
//      print('get_right_most_identifier_type: ${t.type_name}');
      throw 'complete this';
      List<SimpleIdentifier> pis = split_identifiers(rv);
      var ti = get_type_info(pis.first);
      if(ti == null) return null;
      if(ti.alias_name == null){
        DepResolver st = ti.definition_source;
        DepResolver qs = ti.query_source;
        for(var i in pis.sublist(1,pis.length)){
          t = get_type_info( i,
              search_target: st,
              query_source: qs,
              shallow_search:
              query_source != search_target
              );
          if(t == null ) return null;
          st = t.definition_source;
        }
        if(t == null) return null;
        return t;
      }
    }
    //not supported for now.
    if( rv is MethodInvocation) return null;
    throw 'unexpected value ${rv} of type ${rv.runtimeType}';
  }


  ///finds the variable declaration for the given node
  ///Takes SimpleIdentifier representing a variable
  /// If n is an alias, returns null.
  /// Does not set type_name!
  TypeInfo get_declaration_of(
      SimpleIdentifier n,
      DepResolver search_target,
      DepResolver query_source,
      { bool skip_import:false,
      AstNode search_scope:null,
      bool shallow_search:false
      }){
    var r = new TypeInfo()
      ..definition_source = search_target
      ..query_node = n
      ..query_source = query_source
      ..definition_depth_from_query = 0;
    int depth = 0;
    String identifier = n.toString();
    VariableDeclaration d;

    //Func
    bool d_declares_n(d){
      if(d == null) return false;
      if(d.childEntities.first
          .toString() != identifier)
        return false;
      r..definition = d
      ..definition_depth_from_query = depth;
      return true;
    }

    if(search_scope != null){
      d = extract_scope_wide_declaration_of_n_from(
          n.toString(),search_scope);
      if(d_declares_n(d)) return r;
      return null;
    }
    if(shallow_search){
      d = extract_scope_wide_declaration_of_n_from(
          identifier,search_target.ast);
      if(d_declares_n(d)) return r;
      for(var p in search_target.parts){
        d = extract_scope_wide_declaration_of_n_from(
           identifier,p.ast);
        if(d_declares_n(d)) return r;
      }
      return null;
    }

    // Check if n is part of VariableDeclaration
    // and is the variable being defined.
    d = new UpwardSearch<
        VariableDeclaration>(n).result;

    if(d != null){
      if(d_declares_n(d))
        return r;
    }

    // The variable's identifier is defined up the lines
    // or in outer scope.

    //searching local scope
    var b = get_surrounding_block(n);
    List swds = extract_scope_wide_declarations(b);
    if(swds != null)
      for(var d in swds) {
        if(d.offset > n.offset) break;
        if(d.childEntities.first.toString() != identifier )
          continue;
        if(d_declares_n(d)) return r;
      }

    //searching the outer scopes
    b = get_surrounding_block(b);
    depth = -1;
    while(b != null){
      d = extract_scope_wide_declaration_of_n_from(
          identifier,b );
      if(d_declares_n(d)) return r;
      b = get_surrounding_block(b);
      --depth;
    }

    //checking if n is an alias
    for(List pair in search_target.imported_alias_pairs) {
      if(pair[1] == identifier) return null;
    }

    // searching in part files
    for(var ast in search_target.library_asts){
      if(ast == search_target.ast) continue;
      d = extract_scope_wide_declaration_of_n_from(n.toString(),ast);
      if(d_declares_n(d)) return r;
    }

    //dealing with import alias
//    if(n is PrefixedIdentifier){
//      var pfi = extract_prefixed_identifier(n);
//      List<SimpleIdentifier> idens =
//          split_prefixed_identifier(pfi);
//      var left_pref_name = idens.first;
//      for(List imp in _pr.imported_alias_pairs){
//        // skip if alias
//        if(imp[1] == '') continue;
//        if(left_pref_name != imp[1]) continue;
//        //alias matched
//        var l = pfi.toString().split('.').removeAt(0);
//        d = extract_scope_wide_declaration_of_n_from(
//            l.first,imp[0].ast);
//        if(d != null){
//          r[0] = d;r[1] = depth;
//          return r;
//        }
//      }
//    }

    // searching imported files
    if(!skip_import)
      for(List pair in search_target.imported_alias_pairs){
        //No alias
        if(pair[0] == null) continue;
        d = extract_scope_wide_declaration_of_n_from(
            identifier,pair[0].ast);
        if(d_declares_n(d)){
          r.definition_source = pair[0];
          return r;
        }
      }
    return null;//could not find the declaration
  }
  ///Searches up for a FormalParameterList.
  ///
  ///Returns a list of:
  ///
  ///  1. FormalParameter matching
  ///  the identifier of n when stringified
  ///  if such exists. Returns null
  ///  otherwise.
  ///
  ///   2.  The number of scopes moved up
  ///   from the scope n belongs to.
  ///
  TypeInfo get_formal_parameter_of(n){
    TypeInfo ti = new TypeInfo()
      ..query_source = _pr
      ..query_node = n
      ..definition_source = _pr;

    var fl = get_nearest_formal_parameter_list(n);
    if(fl == null) return null;

    List names = extract_arg_names(fl[0]);
    for(var name in names){
      if(name.toString() == n.toString()){
        ti..definition = name.parent
          ..definition_depth_from_query = fl[1];
        return ti;
      }
    }
    return null;
  }

  /// Returns the closest definition of n.
  /// sub blocks are ignored.
  ///
  ///  A guess because it would fail
  /// if a conditional modifies the value
  /// of the variable in runtime.
  ///
  /// e.g.
  ///
  ///     var a = 'hi';
  ///     if(user_input){
  ///       a = new Object();
  ///     }
  ///     //a is an Object not String
  ///
  /// Does not look into constructor.
  /// n can be an alias.
  ///
  List<TypeInfo> guess_effective_definition_of(
      SimpleIdentifier n,
      DepResolver search_target,
      DepResolver query_source,
      { AstNode search_scope:null,
      bool skip_import:false,
      bool shallow_search:false}){

    TypeInfo ti_a = guess_effective_assignment_to(
        n,search_target,query_source,
        search_scope: search_scope,
        skip_import:skip_import,
        shallow_search:shallow_search);

    TypeInfo ti_d = get_declaration_of(
        n,search_target,query_source,
        search_scope: search_scope,
        skip_import:skip_import,
        shallow_search:shallow_search);

    TypeInfo ti_alias = get_alias_match(
        n,search_target: search_target);

    TypeInfo ti_f = get_formal_parameter_of(n);

    if(ti_a == null && ti_alias == null &&
        ti_d == null && ti_f == null )
      return null;


    if(ti_alias != null && ti_a == null &&
        ti_f == null && ti_d == null)
      return [ti_alias];


    if(ti_alias == null && ti_d == null &&
        ti_f == null && ti_a != null)
      return [ti_a];

    if(ti_alias == null && ti_f != null &&
        ti_a == null && ti_d == null){
      return [ti_f];
    }
    if(ti_d != null && ti_a == null &&
      ti_alias == null && ti_f == null)
      return [ti_d];

    // Guessing which declaration or
    // definition takes precedence.
    List<TypeInfo> l = [] ..add(ti_d)
      ..add(ti_a)..add(ti_f)..add(ti_alias);

    l.removeWhere((e)=>e==null);

    // 0 means local scope.
    // -1 means one scope up.
    //Comparator returns negative if a comes before b,
    //0 if equal, positive if a comes after b.
    l.sort((a,b) {
      return b.definition_depth_from_query -
      a.definition_depth_from_query;
    });
    // if AssignmentExpression and
    // VariableDeclaration are
    // in the same scope,
    // AssignmentExpression always
    // takes precedence.
    l.sort((assignment,declaration)=>
      (assignment == ti_a && declaration == ti_d &&
        assignment.definition_depth_from_query ==
          declaration.definition_depth_from_query) ?
      -1:0
    );
    // alias takes precedence
    l.sort((alias,d_a) {
      if (alias != ti_alias) return 0;
      if (d_a == ti_f) return 0;
      return alias.definition_depth_from_query ==
          d_a.definition_depth_from_query ? -1 : 0;
    });

    return l;
  }
  /// Searches for an AssignmentExpression
  /// that is most likely to define the value
  /// of the variable denoted by the identifier
  /// in n.
  ///
  ///  A guess because it would fail
  /// if a conditional modifies the value
  /// of the variable on runtime.
  ///
  /// e.g.
  ///
  ///     var a = 'hi';
  ///     if(user_input){
  ///       a = new Object();
  ///     }
  ///     //a is an Object not String
  ///     //but this function does not
  ///     //know that.
  ///
  /// n must be part of library represented by
  /// _pr.
  /// If n is an alias, returns null.
  ///
  /// +  case 1: local to upward search
  /// +  case 2: scope specific search
  /// +  case 3: import part file search
  ///
  TypeInfo guess_effective_assignment_to(
      SimpleIdentifier n,
      DepResolver search_target,
      DepResolver query_source,
      { bool skip_import:false,
      AstNode search_scope:null,
      bool shallow_search:false}
  ){
    // checks if n is part of a variable declaration
    // Code is mostly duplicate of get_declaration_of
    TypeInfo r = new TypeInfo()
      ..query_node = n
      ..query_source = query_source
      ..definition_source = search_target;
    String identifier = n.toString();
    int count = 0;

    //Function
    bool find_assignment_to(
        String name,AstNode ast){
      //by default searches scope wide only
      List l = extract_assignments_to_n_from(n,ast);
      if(l.isNotEmpty){
        r.definition = l.last;
        r.definition_depth_from_query = count;
        return true;
      }else{
        return false;
      }
    }
    if(search_scope != null){
      if(find_assignment_to(identifier,search_scope)){
        return r;
      }else{
        return null;
      }
    }

    // Searching for the identifier n in a file
    // other than the one where the node n
    // belongs to.
    if(shallow_search){
      if(find_assignment_to(identifier,search_target.ast)){
        r.definition_depth_from_query = -999999999;
        return r;
      }
      for(var p in search_target.parts){
        if(find_assignment_to(identifier,p.ast)){
          r.definition_depth_from_query = -999999999;
          return r;
        }
      }
      return null;
    }

    // Check if n is part of AssignmentExpression
    AssignmentExpression a = new UpwardSearch<
        AssignmentExpression>(n).result;

    if(a != null &&
        a.childEntities.first
            .toString() == identifier){
      r.definition = a;
      r.definition_depth_from_query = 0;
      return r;
    }

    //Search local scope
    var b = get_surrounding_block(n);
    AstNode closest;
    for(var node in extract_assignments_to_n_from(n, b)){
      if(n.offset > node.offset){
        closest = node;
      }else{break;}
    }
    if(closest != null){
      r.definition = closest;
      r.definition_depth_from_query = 0;
      return r;
    }

    //outer scopes
    count = -1;
    b = get_surrounding_block(b);
    while(b != null){
      if(find_assignment_to(n.toString(),b))
        return r;
      b = get_surrounding_block(b);
      --count;
    }

    // Check if n is an alias
    List iap = search_target.imported_alias_pairs;
    for(List pair in iap){
      if(pair[1] == n.toString()){
        return null;
      }
    }

    // the top level scope of the part files
    for(var ast in search_target.library_asts) {
      if(ast == search_target.ast) continue;
      if(find_assignment_to(n.toString(),ast))
        return r;
    }
    // Now imported files
    // If the import has its alias, the caller function
    // must call this function with
    // skip_local_search:true.
    for(List pair in iap){
      if(pair[1] != '') continue;
      if(pair[0] == null) continue;
      if(find_assignment_to(n.toString(),pair[0].ast)){
        r.definition_source = pair[0];
        return r;
      }
    }
    return null;
  }

  /// Extracts all nodes of Type T.
  /// Use filters to remove irrelevant nodes.
  List<T> extract_type_T(
      CompilationUnit extraction_src){
    var v = new Visitor<T>();
    v.visitAllNodes(extraction_src);
    return v.nodes;
  }
  /// Finds the type of the right most identifier.
  /// e.g.  `d` in a node A.b.c.d.hi()`
  /// Returns null if this function fails to
  /// resolve the type.
  TypeInfo get_right_most_identifier_type(
      List<Identifier> identifiers,
      DepResolver search_target,
      DepResolver query_source){
    TypeInfo info = get_type_info(
        identifiers.first,
        search_target:search_target,
        query_source: query_source,
        shallow_search:
        query_source != search_target
        );
    // Functions.
    _set_type_declaration(TypeInfo info){
      TypeInfo cd =  get_class_declaration_of(
          info.type_name,
          search_target: info.definition_source);
      if(cd == null){
        //failed to find the source.
        //class defined in package etc.
        info.type_declaration = null;
        info.type_source = null;
        return;
      };
      info..type_declaration = cd.type_declaration
        ..type_source = cd.type_source;
    }

    // info is needed to determine
    // the scope of search.
    _process_pfi(
        List<SimpleIdentifier> pfi,
        TypeInfo info){
//      print('processing pfi: $pfi');
      for(var i in pfi.getRange(1,pfi.length)){
        // Here i can be:
        // +  class name  .
        // +  variable identifier.
        // +  a field variable.
        if(info.type_declaration == null)
          return null;
        //todo cut down get_type_info's params.
        info = get_type_info(
            i,
            search_target: info.type_source,
            query_source:info.query_source,
            search_scope: info.type_declaration,
            shallow_search:true
        );
//        print('node ${i} is of '
//            'type: ${info.type_name} ');
        if(info == null) return null;
        if(info.type_declaration != null){
          // i is a class name
          continue;
        }else{
          // i is a variable identifier.
          //todo clarify this.
          // not certain what happens if
          // type_name is defined in an aliased
          // import.
          _set_type_declaration(info);
        }
      }
      return info;
    }
    if(info == null) return null;

    //alias
    if(info.alias_name != null){
      info.type_declaration = info?.type_source?.ast;
      return _process_pfi(identifiers, info);
    }
    // A single identifier passed as a List.
    if(identifiers.length == 1){
      return info;
    }
    // pfi consists of either Class name or an
    // class instance and its attribute.
    // No alias.
    if(info.type_declaration == null)
      _set_type_declaration(info);
    if(info.type_declaration == null){
      return null;
    }
    return _process_pfi(identifiers,info);
  }


  /// Search all files, main, part and imported,
  /// for the declaration of  the class that has
  /// an identifier matches the value of name.
  ///
  /// Only sets type_name,
  /// type_declaration,
  /// type_source
  ///
  TypeInfo get_class_declaration_of(
      String name,
      {skip_imports: false,
      DepResolver search_target:null,
      String alias:null}){
    TypeInfo r = new TypeInfo()
      ..type_name = name;
    RegExp klass_name = new RegExp(
        "class\\s${name}[\\s<]+");
    var v = new Visitor<ClassDeclaration>();

    // Function
    bool is_declares(CompilationUnit ast){
      v.visitAllNodes(ast);
      for(var d in v.nodes){
        if(klass_name.hasMatch(d.toString())){
          r.type_declaration = d;
          return true;
        }
      }
      v.nodes = [];
      return false;
    }

    if(search_target.isPart())
      search_target = search_target.main;

    if(alias != null){
      for(var pair in search_target.imported_alias_pairs){
        if(pair[1] != alias) continue;
        if(is_declares(pair[0].ast)){
          r.type_source = pair[0];
          return r;
        }
      }
      return null;
    }

    if(is_declares(search_target.ast)){
      r.type_source = search_target;
      return r;
    }

    var parts = search_target.parts;
    for(var p in parts)
      if(is_declares(p.ast)){
        r.type_source = p;
        return r;
      }
    if(!skip_imports)
      for(var pair in search_target.imported_alias_pairs){
        if(pair[0] != null && is_declares(pair[0].ast)){
          r.type_source = pair[0];
          return r;
        }
      }
    return null;
  }
}


/// If type_name is an import alias,
/// type_name is set to null and
/// alias_name is set and definition
/// is set to CompilationUnit
/// of the file the alias represents.
class TypeInfo{
  /// The node queried.
  AstNode query_node;

  /// File where query_node is defined.
  DepResolver definition_source;

  /// File where query_node is used.
  DepResolver query_source;


  List<TypeInfo> definition_candidates;

  /// File where the declaration of the
  /// type_name occurs.
  DepResolver type_source;

  /// Effective VariableDeclaration or
  /// AssignmentExpression of query_node.
  AstNode definition;

  ///Set only if query_node is an alias.
  String alias_name;

  /// The guesstimate on the type of
  /// the query_node.
  String type_name;

  /// Declaration of the type_name
  /// For an alias, holds the
  /// file it represents.
  AstNode type_declaration;

  /// Hold the number of scopes travelled upward
  /// to find the value [definition].
  int definition_depth_from_query;
  p(){
    print('\tdefinition_source: ${this?.definition_source?.absolute_path}');
    print('\tquery_source: ${this?.query_source?.absolute_path}');
    print('\talias_name: ${this?.alias_name}');
    print('\tquery_node: ${this?.query_node}');
    print('\tdefinition: ${this?.definition}');
    print('\type_declaration: ${this?.type_declaration}');
    print('\ttype_name: ${this?.type_name}');
  }
}

/// Returned by guess_effective_definition_of
///
/// Confusing but a Definitions instance may
/// include `var a;`; strictly speaking a
/// declaration, but in a general sense, it is
/// also the definition of the type of a as
/// dynamic.
///
/// Having moved a scope upward to find the
/// definition/declaration results in a
/// negative depth.
/// If definition/declaration is found locally,
/// depth is set to 0.
///
class Definitions{
  TypeInfo first;
  TypeInfo second;
  TypeInfo third;
  int length;
  p(){
    print('first ${first}, depth${first.definition_depth_from_query}');
  }
}
