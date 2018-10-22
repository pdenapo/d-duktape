import std.stdio;
import etc.c.duktape;


void main()
{
	writeln("Edit source/app.d to start your project.");

	duk_context *ctx = duk_create_heap_default();
    duk_eval_string(ctx, "1+2");
    printf("1+2=%d\n", cast (int) duk_get_int(ctx, -1));
    duk_destroy_heap(ctx);

}
