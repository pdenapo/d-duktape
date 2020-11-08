// This program shows how to embed duketape into your D program

import std.stdio;
import std.string;
import std.conv;
import core.stdc.stdio: printf;
import core.memory;
// The modules to use duketape
import duktape;
import duk_extras.print_alert;

import gnu.readline;

// We want to use a function not declared in the module gnu.readline
// declared in the header readline/history.h
extern (C) 
{
  void add_history (const char *);
}

static void print(string msg)
{
    writeln(msg);
}

/* An example for the duketaped documentation*/
/* A pure D function */
bool is_prime(int val)
{
    int i;
    for (i = 2; i < val; i++) {
        if (val % i == 0) {
            return false;
        }
    }
	return true;
}

// This function does the interface between the D function is_prime and duktape

extern (C) duk_ret_t is_prime_interface(duk_context *ctx) {
    int val = duk_require_int(ctx, 0);
    duk_push_boolean(ctx,is_prime(val));
    return 1;
}

static void push_file_as_string(duk_context *ctx, const char *filename) {
    FILE *f;
    size_t len;
    char* buffer=null;

    f = fopen(filename, "rb");
    if (f) {
        len =  getdelim(&buffer, &len, '\0',f);
        fclose(f);
		// printf("código leído: \n %s \n", buffer);
        duk_push_lstring(ctx, cast(const char *) buffer, cast(duk_size_t) len);
    } else {
        duk_push_undefined(ctx);
    }
}

extern (C) duk_ret_t load(duk_context *ctx) {
    const(char)* file_name = duk_require_string(ctx, 0);
	push_file_as_string(ctx, file_name);
	if (duk_peval(ctx) != 0) {
    /* Use duk_safe_to_string() to convert error into string.  This API
     * call is guaranteed not to throw an error during the coercion.
     */
    printf("Script error: %s\n", duk_safe_to_string(ctx, -1));
}
	duk_pop(ctx);
	duk_pop(ctx);
	return 1;
}



int main()
{
	writeln("Duketape console using d-duktape y GNU Readline");

	duk_context *ctx = duk_create_heap_default();
    if (!ctx) {
        writeln("Failed to create a Duktape heap.");
        return 1;
    }

	// Make sure that it is not collected even if it is no
	// longer referenced from D code (stack, GC heap, …).
	GC.addRoot(cast(void*)ctx);

	// Also ensure that a moving collector does not relocate
	// the object.
	GC.setAttr(cast(void*)ctx, GC.BlkAttr.NO_MOVE);

    scope(exit) {
		// This will be excecuted when we leave the context
		duk_destroy_heap(ctx);
		GC.removeRoot(ctx);
    	GC.clrAttr(ctx, GC.BlkAttr.NO_MOVE);
		}

    duk_push_global_object(ctx);
    duk_print_alert_init(ctx, 0);
    duk_push_c_function(ctx, &is_prime_interface, 1 /*nargs*/);
    // We register a function in the global object to be used from javascript
	duk_put_prop_string(ctx, -2, "is_prime");
	duk_push_c_function(ctx, &load, 1 /*nargs*/);
	duk_put_prop_string(ctx, -2, "load");
	
	while (true) 
	{
		char* line = readline (">");
		if (!line)
        	break; 	
		add_history (line);
		int ret = duk_peval_string(ctx, line);

        if (ret != 0) {
            writeln("Error: " ~ duk_to_string(ctx, -1).to!string);
        }
        else {
            if (!duk_is_undefined(ctx, -1))
                writeln(duk_to_string(ctx, -1).to!string);
        }
        
        duk_pop(ctx);

	} /* end of while loop */

	return 0;
}

