#include <gdnative_api_struct.gen.h>
#include <stdio.h>
#include <hl.h>
#include <hlmodule.h>

#ifdef HL_WIN
#	include <locale.h>
typedef uchar pchar;
#define pprintf(str,file)	uprintf(USTR(str),file)
#define pfopen(file,ext) _wfopen(file,USTR(ext))
#define pcompare wcscmp
#define ptoi(s)	wcstol(s,NULL,10)
#define PSTR(x) USTR(x)
#else
typedef char pchar;
#define pprintf printf
#define pfopen fopen
#define pcompare strcmp
#define ptoi atoi
#define PSTR(x) x
#endif

#ifdef HL_WIN
#	include <windows.h>
#	define dlopen(l,p)		(void*)( (l) ? LoadLibraryA(l) : GetModuleHandle(NULL))
#	define dlsym(h,n)		GetProcAddress((HANDLE)h,n)
#else
#	include <dlfcn.h>
#endif

static hl_code *load_code( const pchar *file ) {
	hl_code *code;
	FILE *f = pfopen(file,"rb");
	int pos, size;
	char *fdata;
	if( f == NULL ) {
		pprintf("File not found '%s'\n",file);
		return NULL;
	}
	fseek(f, 0, SEEK_END);
	size = (int)ftell(f);
	fseek(f, 0, SEEK_SET);
	fdata = (char*)malloc(size);
	pos = 0;
	while( pos < size ) {
		int r = (int)fread(fdata + pos, 1, size-pos, f);
		if( r <= 0 ) {
			pprintf("Failed to read '%s'\n",file);
			return NULL;
		}
		pos += r;
	}
	fclose(f);
	code = hl_code_read((unsigned char*)fdata, size);
	free(fdata);
	return code;
}

typedef void (*setup_func)(godot_gdnative_init_options*);

void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *p_options) {
	struct {
		hl_code *code;
		hl_module *m;
		vdynamic *exc;
	} ctx;
	hl_trap_ctx trap;
	hl_global_init(&ctx);
	pchar *file = PSTR("main.hl");
	ctx.code = load_code(file);
	ctx.m = hl_module_alloc(ctx.code);
	hl_module_init(ctx.m, &p_options);
	hl_code_free(ctx.code);
	hl_trap(trap, ctx.exc, on_exception);

	void* lib = dlopen("hlgodot.hdll", RTLD_LAZY);
	setup_func init = (setup_func)dlsym(lib, "setup");
	init(p_options);

	vclosure c;
	c.t = ctx.code->functions[ctx.m->functions_indexes[ctx.m->code->entrypoint]].type;
	c.fun = ctx.m->functions_ptrs[ctx.m->code->entrypoint];
	c.hasValue = 0;
	hl_dyn_call(&c,NULL,0);
	hl_module_free(ctx.m);
	hl_free(&ctx.code->alloc);
	hl_global_free();

	printf("Hello, world!");

	return;

	on_exception:
	{
		varray *a = hl_exception_stack();
		int i;
		uprintf(USTR("Uncaught exception: %s\n"), hl_to_string(ctx.exc));
		for(i=0;i<a->size;i++)
			uprintf(USTR("Called from %s\n"), hl_aptr(a,uchar*)[i]);
		hl_debug_break();
	}
	hl_global_free();
}
