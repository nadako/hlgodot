import Godot;

class Main {
	static function main() {
		inline function b(s:String) return @:privateAccess s.toUtf8();
		Godot.print_warning(b("Hi from Haxe"), b("some func"), b("some file"), 42);
	}
}
