import haxe.DynamicAccess;
import haxe.macro.Expr;
using StringTools;

typedef Root = {
	var core:Api;
	var extensions:DynamicAccess<Api>;
}

typedef Api = {
	var type:String;
	var version:{major:Int, minor:Int};
	var api:Array<ApiMethod>;
}

typedef ApiMethod = {
	var name:String;
	var return_type:String;
	var arguments:Array<ApiMethodArg>;
}

abstract ApiMethodArg(Array<String>) {
	public var type(get,never):String; inline function get_type() return this[0];
	public var name(get,never):String; inline function get_name() return this[1];
}

class Main {
	static function prepareType(t:String):String {
		if (t.startsWith("const ")) return t.substring("const ".length);
		return t;
	}

	static function getType(t:String):{prim:String, ct:ComplexType} return switch prepareType(t) {
		case "void": {prim: "_VOID", ct: macro : Void};
		case "char *": {prim: "_BYTES", ct: macro : hl.Bytes};
		case "godot_int" | "int": {prim: "_I32", ct: macro : Int};
		case "godot_real": {prim: "_F32", ct: macro : Single};
		case "godot_bool": {prim: "_BOOL", ct: macro : Bool};
		case "int64_t": {prim: "_I64", ct: macro : hl.I64};
		case "double": {prim: "_F64", ct: macro : Float};
		case "wchar_t": {prim: "_I16", ct: macro : hl.UI16};
		case _: {prim: "_VOID", ct: macro : Void}; // throw 'Unknown type `$t`';
	}

	static function main() {
		var api:Root = haxe.Json.parse(sys.io.File.getContent("../godot_headers/gdnative_api.json"));

		var godotPrefix = "godot_";
		var gluePrefix = "hlgodot_";

		var glueContent = [
			[
				'#define HL_NAME(n) $gluePrefix##n',
				'#include <hl.h>',
				"#include <gdnative_api_struct.gen.h>"
			].join("\n"),
			[
				"const godot_gdnative_core_api_struct *_gdnative_wrapper_api_struct;",
				"const godot_gdnative_ext_nativescript_api_struct *_gdnative_wrapper_nativescript_api_struct;",
				"const godot_gdnative_ext_pluginscript_api_struct *_gdnative_wrapper_pluginscript_api_struct;",
				"const godot_gdnative_ext_arvr_api_struct *_gdnative_wrapper_arvr_api_struct;",
			].join("\n"),
			"EXPORT void setup(godot_gdnative_init_options* options) { GDNATIVE_API_INIT(options); }",
		];

		var externFields:Array<Field> = [];

		for (method in api.core.api) {
			if (!method.name.startsWith(godotPrefix))
				throw 'Method ${method.name} does not start with the prefix `$godotPrefix`';

			var unprefixedName = method.name.substring(godotPrefix.length);
			var glueMethodName = gluePrefix + unprefixedName;
			var glueMethodArgs = [];
			var glueCallArgs = [];

			var ret = getType(method.return_type);
			var primReturnType = ret.prim;
			var externReturnType = ret.ct;
			var primArgTypes = [];
			var externArgs:Array<FunctionArg> = [];

			for (arg in method.arguments) {
				glueMethodArgs.push('${arg.type} ${arg.name}');
				glueCallArgs.push(arg.name);
				var t = getType(arg.type);
				primArgTypes.push(t.prim);
				externArgs.push({name: arg.name, type: t.ct});
			}

			externFields.push({
				pos: null,
				name: unprefixedName,
				access: [AStatic],
				kind: FFun({
					args: externArgs,
					ret: externReturnType,
					expr: null
				})
			});

			glueContent.push([
				'HL_PRIM ${method.return_type} HL_NAME($glueMethodName)(${glueMethodArgs.join(", ")}) {',
				'\t${if (method.return_type != "void") "return " else ""}_gdnative_wrapper_api_struct->${method.name}(${glueCallArgs.join(", ")});',
				'}',
				'DEFINE_PRIM($primReturnType, $glueMethodName, ${if (primArgTypes.length == 0) "_NO_ARG" else primArgTypes.join(" ")})',
			].join("\n"));
		}

		var def:TypeDefinition = {
			pos: null,
			pack: [],
			name: "Godot",
			isExtern: true,
			meta: [
				{pos: null, name: ":hlNative", params: [
					{pos: null, expr: EConst(CString("hlgodot"))},
					{pos: null, expr: EConst(CString(gluePrefix))},
				]}
			],
			kind: TDClass(),
			fields: externFields,
		};
		sys.io.File.saveContent("../externs/Godot.hx", new haxe.macro.Printer().printTypeDefinition(def, false));

		sys.io.File.saveContent("../externs/hlgodot.c", glueContent.join("\n\n"));
	}
}
