part of custom_resolver;
/// The file manager for the Resolver class.
///
///
/// As the Resolver class only support local code,
/// does no look into packages or dart library code.
class DepResolver {
  //matches import directive
  static final RegExp import_m = new RegExp(
      r'^\s*import\s+'+'(\"|\').+(\'|\").*;');
  //matches part directive
  static final RegExp part_of_m = new RegExp(
      '(^|;)\\s*part\\s+of\\s+.+?;');
  //matches within quotes.
  // No look-behind in javascript.
  //use \0 to fetch the string.
  static final RegExp import_string_m = new RegExp(
      '.*\'([\\w:./]+)(?=\')|.*\"([\\w_/.:]+)(?=\")'
  );

  List<DepResolver> parts = [];
  DepResolver _main;

  String _file_dir;
  String absolute_path;
  CompilationUnit ast;
  var _statements;
  List<String> import_strings = [];

  //<path, alias>
  Map<String, String> import_path_alias = {};

  //<path,PartsResolver>
  static Map<String,DepResolver> _cache = {};
  DepResolver get_dep_resolver(String alias){
    for(var pair in imported_alias_pairs){
      if(pair[1] == alias)
        return pair[0];
    }
    return null;
  }

  //prevents fetching the same file twice
  //key: path, value: PartsResolver object
  factory DepResolver( String entry_point_path) {
    if(_cache.containsKey(entry_point_path))
      return _cache[entry_point_path];
    return new DepResolver.create_from_file(
        entry_point_path);
  }
  factory DepResolver.from_string(
      String entry_point,String code) {
    if(_cache.containsKey(entry_point))
      if(code != ''){
        _cache[entry_point] = new DepResolver
            .create_from_string(
              code,entry_point );
      }else{
        return _cache[entry_point];
      }
    return new DepResolver.create_from_string(
        code,entry_point);
  }
  DepResolver.create_from_file(String path){
    absolute_path = Path.absolute(path);
    _file_dir = Path.absolute(Path.dirname(path));

    ast = parseDartFile(absolute_path,
        suppressErrors: false,parseFunctionBodies: true);
    initialize(path);
  }
  DepResolver.create_from_string(
      String code, String path){
    absolute_path = Path.absolute(path);
    _file_dir = Path.absolute(Path.dirname(path));
    ast = parseCompilationUnit(code,
        suppressErrors: false,parseFunctionBodies: true);
    initialize(path);
  }
  set main(DepResolver pr){
    _main = pr;
  }
  get main=>_main;
  toSource(){
    return ast.toSource();
  }

  initialize(String path) {
    _statements = ast.directives;
    _process_parts();
    _process_imports();
    _cache[path] = this;
  }
  void _process_parts() {
    List paths = _extract_all_part_file_paths();
    if(paths.length == 0) return;
    for (var path in paths) {
      var pr = new DepResolver(path);
      pr.main = this;
      parts.add(pr);
      _cache[path] = pr;
    }
  }
  void _process_imports(){
    var alias;
    String path;
    for(var e in _statements){
      if(e is! ImportDirective) continue;
      path = import_string_m.firstMatch(
          e.toString()).group(1).trim();
      //not dealing with packages or dart libs
      // for the time being

      alias = e.toString().split(' as ');
      alias = alias.length > 1 ? alias.last : '';
      alias = alias.replaceAll(';','').trim();

      if(_is_relative_import(path)){
        import_strings.add(path);
        path = to_abs_path(path);
        _cache[path] = new DepResolver(path);
      }
      import_path_alias[path] = alias;
      import_strings.add(path);
    }
  }
  bool _is_relative_import(String s){
    if(s.indexOf('package:') == 0)
      return false;
    if(s.indexOf('dart:')==0)
      return false;
    return true;
  }


  List<String> _extract_all_part_file_paths() {
    List<String> abs_paths = [];

    for (var e in _statements) {
      if (e is PartDirective) {
        //todo find a cleaner solution
        e = e.toSource();
        if(e.contains('part of')) continue;
        e = e.replaceFirst('part', '')
            .replaceAll('\'', '')
            .replaceAll('\"', '')
            .replaceAll(';', '')
            .trim();
        abs_paths.add(to_abs_path(e));
      }
    }
    return abs_paths;
  }

  to_abs_path(path){
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
    path = context.join(_file_dir,path);
    return context.normalize(path);
  }

  is_imported(String package_name){
    if(isPart())
      import_strings = _main.import_strings;
    if(_is_relative_import(package_name)){
      package_name = to_abs_path(package_name);
    }
    for(var s in import_strings){
      if(s == package_name) return true;
    }
    return false;
  }
  bool isPart()=> _main != null;

  //todo support alias and package imports
  /// Returns [[CompilationUnit, alias],...]
  List<CompilationUnit> get library_asts{
    List<CompilationUnit> r = [];
    var pr = isPart() ? _main : this;
    r.add(pr.ast);
    for(var p in pr.parts){
      r.add(p.ast);
    }
    return r;
  }
  /// Returns [[PartResolver, alias],...]
  /// alias may be null.
  ///
  /// PartResolver is set to null if
  /// alias represents a package or
  /// dart-sdk lib.
  List<List> get imported_alias_pairs{
    List<List> r = [];
    var pr = isPart() ? _main : this;
    for(String path in pr.import_path_alias.keys){
      DepResolver i = _cache[path];
      if(i != null){
        r.add([
          i, import_path_alias[path]
        ]);
      }else{
        //todo PartResolver should not be null
        //it's adding too many `?.`.
        r.add([null, import_path_alias[path]]);
      }
    }
    return r;
  }
}
