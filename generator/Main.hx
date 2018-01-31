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

enum CType {
	Pointer(t:CType);
	Name(t:String);
}

class Main {
	static var abstracts = new Map<String,{t:String, hxName:String}>();

	static function parseType(t:String):CType {
		t = t.trim();
		if (t.endsWith("*")) return Pointer(parseType(t.substring(0, t.length - 1)));
		if (t.startsWith("const ")) return parseType(t.substring("const ".length));
		return Name(t);
	}

	static function addAbstract(t:String) {
		var unprefixed = t.substring("godot_".length);
		var primName = "_G" + unprefixed.toUpperCase();
		var hxName = "G" + unprefixed.split("_").map(p -> p.charAt(0).toUpperCase() + p.substring(1)).join("");
		abstracts[primName] = {t: t, hxName: hxName};
		return {primName: primName, hxName: hxName};
	}

	static function isGodotStruct(t:String) return t.startsWith("godot_") && switch t {
		case "godot_bool" | "godot_real" | "godot_int": false;
		case _: true;
	}

	static function getType(t:CType):{prim:String, ct:ComplexType, ptr:Bool} return switch t {
		case Pointer(Name("char")): {prim: "_BYTES", ct: macro : hl.Bytes, ptr: false};
		case Pointer(Name(t)) if (isGodotStruct(t)):
			var a = addAbstract(t);
			{prim: a.primName, ct: TPath({pack: [], name: a.hxName}), ptr: false}
		case Pointer(t): var i = getType(t), ct = i.ct; {prim: '_REF(${i.prim})', ct: macro : hl.Ref<$ct>, ptr: false};
		case Name(t): switch t {
			case "void": {prim: "_VOID", ct: macro : Void, ptr: false};
			case "godot_int" | "int": {prim: "_I32", ct: macro : Int, ptr: false};
			case "godot_real": {prim: "_F32", ct: macro : Single, ptr: false};
			case "godot_bool": {prim: "_BOOL", ct: macro : Bool, ptr: false};
			case "uint8_t": {prim: "_I8", ct: macro : hl.UI8, ptr: false};
			case "int64_t" | "uint64_t": {prim: "_I64", ct: macro : hl.I64, ptr: false};
			case "uint32_t": {prim: "_I32", ct: macro : Int, ptr: false};
			case "size_t": {prim: "_I32", ct: macro : Int, ptr: false}; // TODO: platform-specific
			case "double": {prim: "_F64", ct: macro : Float, ptr: false};
			case "signed char": {prim: "_I8", ct: macro : hl.UI8, ptr: false};
			case "wchar_t": {prim: "_I16", ct: macro : hl.UI16, ptr: false};
			case _ if (isGodotStruct(t)):
				var a = addAbstract(t);
			 	{prim: a.primName, ct: TPath({pack: [], name: a.hxName}), ptr: true};
			case "native_call_cb": {prim: "_VOID", ct: macro : Void, ptr: false}; // TODO: vclosure
			case _: throw 'Unknown type `$t`';
		}
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
		var defines = [];

		for (method in api.core.api) {
			if (!method.name.startsWith(godotPrefix))
				throw 'Method ${method.name} does not start with the prefix `$godotPrefix`';

			var unprefixedName = method.name.substring(godotPrefix.length);
			var glueMethodName = gluePrefix + unprefixedName;
			var glueMethodArgs = [];
			var glueCallArgs = [];

			var ret = getType(parseType(method.return_type));
			var primReturnType = ret.prim;
			var externReturnType = ret.ct;
			var primArgTypes = [];
			var externArgs:Array<FunctionArg> = [];

			for (arg in method.arguments) {
				var t = getType(parseType(arg.type));
				glueMethodArgs.push('${if (t.ptr) arg.type + "*" else arg.type} ${arg.name}');
				glueCallArgs.push(if (t.ptr) "*" + arg.name else arg.name);
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

			var call = '_gdnative_wrapper_api_struct->${method.name}(${glueCallArgs.join(", ")})';
			var expr =
				if (method.return_type == "void")
					'\t$call;'
				else if (ret.ptr)
					[
						'\t${method.return_type}* __ret = (${method.return_type}*)hl_gc_alloc_noptr(sizeof(${method.return_type}));',
						'\t*__ret = $call;',
						'\treturn __ret;',
					].join("\n")
				else
					'\treturn $call;';

			glueContent.push([
				'HL_PRIM ${method.return_type + if (ret.ptr) "*" else ""} HL_NAME($glueMethodName)(${glueMethodArgs.join(", ")}) {',
				expr,
				'}',
			].join("\n"));

			defines.push('DEFINE_PRIM($primReturnType, $glueMethodName, ${if (primArgTypes.length == 0) "_NO_ARG" else primArgTypes.join(" ")})');
		}

		glueContent.push([for (name in abstracts.keys()) '#define $name _ABSTRACT(${abstracts[name].t})'].join("\n"));

		glueContent.push(defines.join("\n"));

		var defs = [];

		var printer = new haxe.macro.Printer();

		for (t in abstracts) {
			defs.push(printer.printTypeDefinition({
				pos: null,
				pack: [],
				name: t.hxName,
				kind: TDAlias(TPath({pack: ["hl"], name: "Abstract", params: [TPExpr({pos: null, expr: EConst(CString(t.t))})]})),
				fields: [],
			}));
		}
		defs.push("\n");

		defs.push(printer.printTypeDefinition({
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
		}));

		sys.io.File.saveContent("../externs/Godot.hx", defs.join("\n"));

		sys.io.File.saveContent("../externs/hlgodot.c", glueContent.join("\n\n"));
	}
}
