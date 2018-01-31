import Godot;

class Main {
	static function main() {
		var s = Godot.string_chars_to_utf8(@:privateAccess "Hello, world".bytes);
		Godot.print(s);
	}
}
