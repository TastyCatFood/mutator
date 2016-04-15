part of custom_resolver;
///Functions that do not depend on Resolver
///field values.
AstNode get_surrounding_block(node){
  if(node == null) return null;
  while(true){
    if(node.parent == null) return null;
    node = node.parent;
    if(is_scope(node))
    return node;
  }
}
extract_scope_wide_declaration_of_n_from(
      String identifier_name, AstNode block){
    var l = extract_scope_wide_declarations(block);
    for(var d in l) {
      var v = d.childEntities.first;
      if(v.toString() == identifier_name){
        return d;
      }
    }
    return null;
}

///Returns true if the given node has its
///scope.
///Returns also true for:
/// MethodDeclaration
/// FunctionDeclaration
/// CompilationUnit
/// ClassDeclaration
///
///as they have a scope.
bool is_scope(node){
    if(node is Block||
        node is CompilationUnit ||
        node is Block||
        //below are for extracting arguments
        node is MethodDeclaration ||
        node is FunctionDeclaration ||
        node is ConstructorDeclaration||
        //FieldDeclarations
        node is ClassDeclaration ||
        //Block should cover these but jus in case
        node is IfStatement ||
        node is WhileStatement||
        node is DoStatement ||
        node is TryStatement ||
        node is SwitchStatement) return true;
    return false;
}

///Fetch declarations that have effect in
///all the children blocks of the given node.
///Does not cover FormalParameterList.
///Does not enter a node that is a block.
List extract_scope_wide_declarations(AstNode node){
  if(node == null) return [];
  var nodes = [];
  var declarations = [];
  nodes.addAll(node.childEntities);

  //pushing more nodes and skipping blocks
  while(nodes.isNotEmpty){
    var e = nodes.removeAt(0);
    if(e is! AstNode) continue;
    if(e is VariableDeclaration){
      declarations.add(e);
      continue;
    }
    if(!is_scope(e) && e is AstNode){
      nodes.addAll(e.childEntities);
      continue;
    }
  }
  return declarations;
}


///Searches for all declarations
//List<AstNode> extract_all_declarations_in(
//    AstNode node){
//  var nodes = [];
//  var de = new DeclarationExtractor(nodes);
//  node?.visitChildren(de);
//  return nodes;
//}

/// Takes a VariableDeclaration node.
/// Returns a ConstructorName node or
/// rvalue; includes MethodInvocation.
/// todo write test
extract_rvalue(n){
  var nodes = flatten_tree(n,1);
  for(var node in nodes){
    if(node is Literal) return node;
    if(node is TypeName){
      return node;
    }
    if(node is InstanceCreationExpression)
      for(var e in node.childEntities)
        if(e is ConstructorName) return e;
    if(node is MethodInvocation){
      return node;
    }
  }
  //rvalue is a variable or null;
  return nodes.length > 1 ? nodes.last : null;
}
///Searches scopes upward for an
///AssignmentExpression for the
///variable denoted by the identifier
///in n.
///
/// Returns a list of AssignmentExpression
extract_assignments_to_n_from(
    SimpleIdentifier n,
    AstNode in_scope,
    [int search_depth=2]){
  var nodes = flatten_tree(in_scope,search_depth)
      .where((e)=>e is AssignmentExpression);
  var r = [];
  for(AstNode node in nodes){
    String i = node.childEntities.first.toString();
    if(i == n.toString()){
      r.add(node);
    }
  }
  return r;
}

///Takes any node.
///
///Searches scopes upward to find
///the closest FormalParameterList
///
/// Returns a list of
///   1.  FormalParameterList
///   2.  Its depth relative to n
///
/// Or null.
///

List get_nearest_formal_parameter_list(n){
  var r = new List(2);
  int count = 0;
  while(true){
    if(n is FunctionDeclaration ||
        n is MethodDeclaration ||
        n is ConstructorDeclaration)
      break;
    n = get_surrounding_block(n);
    --count;
    if(n == null) return n;
  }
  for(var e in n.childEntities){
    if(e is FormalParameterList){
      r[0] = e;r[1] = count;
      return r;
    }
  }
  //empty FormalParameterList
  return null;
}

///Takes:
///FunctionDeclaration
///FunctionExpression
///FormalParameterList
///
///Returns:
///Positional argument names :e.g. a and b in `f(a,b){return a+b;}`
///Named option names:e.g. your_name in `f({String your_name}){...}`
///
List<SimpleIdentifier> extract_arg_names(AstNode n){
  var fpl;
  if(n is! FormalParameterList){
    for(var e in flatten_tree(n)){
      if(e is FormalParameterList){
        fpl = e;
        break;
      }
    }
  }else if(n is FormalParameterList){
    fpl = n;
  }
  //todo test with optional parameter or default param
  var r = [];
  for(var c in fpl.childEntities){
    if(c is! FormalParameter)
      continue;
    for(var cc in c.childEntities){
      //filtering String int etc
      if(cc is! TypeName){
        r.add(cc);
        break;
      }
    }
  }
  return r;
}

List flatten_tree(AstNode n,[int depth=9999999]){
  var que = [];
  que.add(n);
  var nodes = [];
  int nodes_count = que.length;
  int dep = 0;
  int c = 0;
  if(depth == 0) return [n];
  while(que.isNotEmpty){
    var node = que.removeAt(0);
    if(node is! AstNode) continue;
    for(var cn in node.childEntities){
      nodes.add(cn);
      que.add(cn);
    }
    //Keeping track of how deep in the tree
    ++c;
    if(c == nodes_count){
      ++ dep; // One level done
      if(depth <= dep) return nodes;
      c = 0;
      nodes_count = que.length;
    }
  }
  return nodes;
}

List<MethodInvocation> extract_method_invocation(
    AstNode n){
  var v = new _MethodInvocationVisitor();
  //With BreadthFirstVisitor visitor takes the tree.
  v.visitAllNodes(n);
  return v.nodes;
}
show(node){
  print('Type: ${node.runtimeType}, body: $node');
}


VariableDeclaration extract_field_declaration_of(
  RegExp attribute_name,ClassDeclaration cd ){
  for(var c in flatten_tree(cd,2)){
    if(c is! VariableDeclaration) continue;
    if(attribute_name.hasMatch(c.toString()))
    return c;
  }
  return null;
}
/// Checks if the invocation/assignment/access is
/// being performed on a class member or an alias.
///
/// Returns the node `A.b.c` in `A.b.c.hi();` .
/// If no prefixedIdentifier is found,
/// returns null.
///
/// Note: instance or class name is not a prefix.
///
/// For a static member and instance member,
/// what is considered a PrefixedIdentifier differ
/// from a simple variable:
///
///     Type: PropertyAccessImpl, body: p.A.d.on(p.e).greetings
///     Type: MethodInvocationImpl, body: p.A.d.on(p.e)
///     Type: PropertyAccessImpl, body: p.A.d
///     Type: PrefixedIdentifierImpl, body: p.A
///
///     Type: PropertyAccessImpl, body: p.d2.on(p.e).f
///     Type: MethodInvocationImpl, body: p.d2.on(p.e)
///     Type: PrefixedIdentifierImpl, body: p.d2
///
/// Identifier is basically a function name or variable.
/// A field variable is considered a property.
PrefixedIdentifier extract_prefixed_identifier(
      AstNode n) {
  if(n == null) return null;
  AstNode pfi = n;
  var t = n.childEntities.first;
  while(t != null){
//    show(t);
    if(t is PrefixedIdentifier){
      pfi = t;
      break;
    }
    if(t is Token) return null;
    t = t.childEntities.first;
  }
  return pfi;
}
PropertyAccess extract_PropertyAccess(
    AstNode n) {
  if(n == null) return null;
  AstNode pfi = n;
  var t = n.childEntities.first;
  while(t != null){
//    show(t);
    if(t is PropertyAccess){
      pfi = t;
      break;
    }
    if(t is Token) return null;
    t = t.childEntities.first;
  }
  return pfi;
}

split_identifiers(dynamic i){
  if(i == null) return null;
  if(i is SimpleIdentifier) return [i];
  List r = [];
  var v = new GVisitor();
  i.visitChildren(v);
  for(var c in v.nodes){
    if(c is Token) continue;
    if(c is SimpleIdentifier) r.add(c);
  }
  return r;
}
class UpwardSearch<T>{
  /// node must be a simple identifier
  /// or AstNode.
  T result;
  int depth = 0;
  UpwardSearch(node){
    if(node == null){
      result = null;
      return;
    }
    while(true){
      node = node.parent;
      if(is_scope(node)) --depth;
      if(node is T){
        result = node;
        return;
      }
      if(node.parent == null) {
        result = null;
        return;
      }
    }
  }
}

/// Pass only a SimpleFormalParameter or
/// Declaration.
TypeName _extract_TypeName_from(d){
  if(d == null) return null;
  for(var t in d.childEntities){
    if(t is TypeName) return t;
  }
}

FieldDeclaration get_field_declaration_of(
  String name, ClassDeclaration c){
  var v = new Visitor<FieldDeclaration>();
  for(var node in v.nodes){
    print(node.childEntities.first);
  }
  return null;
}
//[type_name, alias], [type_name, null] or null
List<String> _as_expression_to_type_alias_pair(AsExpression a){
  //deal with alias
  return [a.childEntities.last.toString(),null];
}



class _MethodInvocationVisitor extends BreadthFirstVisitor{
  List<AstNode> nodes = [];
  _MethodInvocationVisitor():super(){ }
  @override
  visitMethodInvocation(MethodInvocation n){
    nodes.add(n);
    super.visitMethodInvocation(n);
  }
}

class Visitor<T> extends BreadthFirstVisitor<T>{
  List<AstNode> nodes = [];
  Visitor():super(){ }
  @override
  visitNode(AstNode n){
//    Resolver.show(n);
    if(n is T) nodes.add(n);
    super.visitNode(n);
  }
}
class GVisitor extends GeneralizingAstVisitor{
  List<AstNode> nodes = [];
  GVisitor():super(){ }
  @override
  visitNode(AstNode n){
//    Resolver.show(n);
    nodes.add(n);
    super.visitNode(n);
  }

}
