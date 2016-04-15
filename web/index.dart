library main;

import 'package:mistletoe/mistletoe.dart';
import 'import_this.dart' as p;
part 'b.dart';

var d_t  = new Dynamism(expert:true);
void main(){
  var e = new Object();
  d_t.on(e).greetings = 'hi from mistletoe';
}