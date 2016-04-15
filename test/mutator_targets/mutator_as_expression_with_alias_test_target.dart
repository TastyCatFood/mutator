import './imported_file.dart' as imp;
f(e,t){
  e = (e as imp.B);
  e.on(t).greetings = 'hi';
}
main(){
  f(new imp.B(),new Object());
}

