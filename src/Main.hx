import haxe.DynamicAccess;
import haxe.macro.Expr;
using StringTools;

typedef GClass = {
	var name:String;
	var base_class:String;
	var api_type:String;
	var singleton:Bool;
	var instanciable:Bool;
	var is_reference:Bool;
	var constants:DynamicAccess<Int>;
	var properties:Array<GProperty>;
	var signals:Array<GSignal>;
	var methods:Array<GMethod>;
	var enums:Array<GEnum>;
}

typedef GProperty = {
	var name:String;
	var type:String;
	var getter:String;
	var setter:String;
	var index:Int;
}

typedef GSignal = {
	var name:String;
	var arguments:Array<GSignalArg>;
}

typedef GSignalArg = {
	var name:String;
	var type:String;
	var default_value:String;
}

typedef GMethod = {
	var name:String;
	var return_type:String;
	var is_editor:Bool;
	var is_noscript:Bool;
	var is_const:Bool;
	var is_reverse:Bool;
	var is_virtual:Bool;
	var has_varargs:Bool;
	var is_from_script:Bool;
	var arguments:Array<GMethodArg>;
}

typedef GMethodArg = {
	var name:String;
	var type:String;
	var has_default_value:Bool;
	var default_value:String;
}

typedef GEnum = {
	var name:String;
	var values:DynamicAccess<Int>;
}

class Main {
	static function stripName(s:String):String return if (s.fastCodeAt(0) == "_".code) s.substring(1) else s;

	static function escapeIdent(s:String):String return switch s {
		case
			  "import"
			| "var"
			| "default"
			| "class"
			| "interface"
			| "override"
			| "in"
			| "function"
			| "new"
			:
				s + "_";
		case _: s;
	}

	static function convertType(s:String):ComplexType return switch s {
		case "void": macro : Void;
		case "int": macro : Int;
		case "bool": macro : Bool;
		case "float": macro : Float; // float32?
		case "Array": macro : GArray;
		case _ if (s.startsWith("enum.")):
			s = s.substring("enum.".length);
			var parts = s.split("::");
			var name = parts.map(stripName).join("");
			TPath({pack: [], name: name});
		case _:
			TPath({pack: [], name: stripName(s)});
	}

	static function convertHlType(s:String):String return switch s {
		case "void": "_VOID";
		case "int": "_I32";
		case "bool": "_BOOL";
		case "float": "_F64";
		case _: "_GODOT_OBJECT";
	}

	static function convertGlueType(s:String):String return switch s {
		case "void" | "int" | "bool": s;
		case "float": "double";
		case _ if (s.startsWith("enum.")): "int";
		case _: "godot_object*";
	}

	static function main() {
		var classes:Array<GClass> = haxe.Json.parse(sys.io.File.getContent("api.json"));
		var output = [
			"import GodotBase;",
		];
		var gluePrefix = "godot_";
		var glue = [
			['#define HL_NAME(n) ${gluePrefix}_##n', "#include <hl.h>"].join("\n"),
			[
				'HL_PRIM void HL_NAME(${gluePrefix}___destroy)(godot_object* obj) {',
				'\tapi->godot_object_destroy(obj);',
				'}'
			].join("\n"),
			"#define _GODOT_OBJECT _ABSTRACT(godot_object);",
		];

		var printer = new haxe.macro.Printer();
		for (cls in classes) {
			var externClassName = stripName(cls.name);
			var fields:Array<Field> = [];

			if (cls.instanciable) {
				var ctorMethodName = gluePrefix + externClassName + "___new";
				glue.push([
					'HL_PRIM godot_object* HL_NAME($ctorMethodName)() {',
					'\tstatic godot_class_constructor ctor = NULL;',
					'\tif (ctor == NULL)',
					'\t\tctor = api->godot_get_class_constructor("${cls.name}");',
					'\treturn ctor();',
					'}'
				].join("\n"));
			}

			for (method in cls.methods) {
				var externMethodName = escapeIdent(method.name);
				var access = if (cls.singleton) [AStatic] else [];
				var args:Array<FunctionArg> = [];

				var glueArgs = [];
				var glueArgsSetup = [];
				var hlArgTypes = [];
				var glueMethodPrelude;

				var glueMethodCallInstance;
				if (!cls.singleton) {
					glueArgs.push("godot_object* __obj");
					hlArgTypes.push("_GODOT_OBJECT");
					glueMethodCallInstance = "__obj";
					glueMethodPrelude = "";
				} else {
					glueMethodCallInstance = "__singleton_" + externClassName;
					var initMethodName = '${glueMethodCallInstance}__init';
					glue.push('static godot_object* $glueMethodCallInstance;');
					glue.push([
						'inline void $initMethodName() {',
						'\tif ($glueMethodCallInstance == NULL)',
						'\t\t$glueMethodCallInstance = api->godot_global_get_singleton("${cls.name}")',
						'}',
					].join("\n"));
					glueMethodPrelude = '\t$initMethodName();';
				}

				for (arg in method.arguments) {
					var externArgName = escapeIdent(arg.name);
					args.push({
						name: externArgName,
						type: convertType(arg.type),
					});
					var glueArgType = convertGlueType(arg.type);
					glueArgs.push('$glueArgType $externArgName');
					glueArgsSetup.push('\t\t&$externArgName,');
					hlArgTypes.push(convertHlType(arg.type));
				}
				fields.push({
					pos: null,
					name: externMethodName,
					access: access,
					kind: FFun({
						args: args,
						ret: convertType(method.return_type),
						expr: null
					})
				});

				var glueReturnType = convertGlueType(method.return_type);
				var glueMethodName = gluePrefix + externClassName + "_" + externMethodName;
				glue.push([
					'HL_PRIM $glueReturnType HL_NAME($glueMethodName)(${glueArgs.join(", ")}) {',
					glueMethodPrelude,
					"\tstatic godot_method_bind* __mb = NULL;",
					"\tif (__mb == NULL)",
					'\t\t__mb = __api->godot_method_bind_get_method("${cls.name}", "${method.name}")',
					'\tconst void* __args[${method.arguments.length}] = {',
					glueArgsSetup.join("\n"),
					"\t}",
					if (glueReturnType == "void") "" else '\t$glueReturnType __ret;',
					'\tapi->godot_method_bind_ptrcall(__mb, $glueMethodCallInstance, __args, ${if (glueReturnType == "void") "NULL" else "&__ret"});',
					if (glueReturnType == "void") "" else "\treturn __ret;",
					'}'
				].join("\n"));

				var hlReturnType = convertHlType(method.return_type);
				glue.push('DEFINE_PRIM($hlReturnType, $glueMethodName, ${if (hlArgTypes.length == 0) "_NO_ARG" else hlArgTypes.join(" ")})');
			}

			// TODO: preserve order
			for (constant in cls.constants.keys()) {
				fields.push({
					pos: null,
					name: constant,
					access: [AStatic, AInline],
					kind: FVar(null, {pos: null, expr: EConst(CInt(Std.string(cls.constants[constant])))})
				});
			}

			for (enm in cls.enums) {
				var fields:Array<Field> = [];
				// TODO: preserve order
				for (field in enm.values.keys()) {
					fields.push({
						pos: null,
						name: field,
						kind: FVar(null, {pos: null, expr: EConst(CInt(Std.string(enm.values[field])))})
					});
				}
				var def:TypeDefinition = {
					pos: null,
					pack: [],
					name: externClassName + stripName(enm.name),
					kind: TDAbstract(macro : Int),
					meta: [{name: ":enum", pos: null}],
					fields: fields,
				}
				output.push(printer.printTypeDefinition(def));
			}

			var superClass:TypePath = if (cls.base_class == "") null else {pack: [], name: cls.base_class};

			var def:TypeDefinition = {
				pos: null,
				pack: [],
				name: externClassName,
				kind: TDClass(superClass),
				isExtern: true,
				fields: fields,
			};
			output.push(printer.printTypeDefinition(def));
		}
		sys.io.File.saveContent("Godot.hx", output.join("\n\n"));
		sys.io.File.saveContent("godot.h", glue.join("\n\n"));
	}
}
