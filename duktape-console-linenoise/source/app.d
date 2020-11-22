// This program shows how to embed duketape into your D program

import std.stdio;
import std.string;
import std.conv;
import core.stdc.stdio: printf;
import core.memory;
// The modules to use duketape
import duktape;
import duk_extras.print_alert;
import d_duktape;
import deimos.linenoise;

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

// print the message many times, for example:
// print_many(5,"hola")

static void print_many(int times,string msg)
{
  for (int i=0;i<times;i++)
    writeln(msg);
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

// We define the possible completions for linenoise

extern(C) void completion(const char *buf, linenoiseCompletions *lc) {
    if (buf[0] == 'a') {
        linenoiseAddCompletion(lc,"alert");
    }
    else if (buf[0] == 'p') {
        linenoiseAddCompletion(lc,"print");
        linenoiseAddCompletion(lc,"print_many");
    }
    else if (buf[0] == 'i') {
        linenoiseAddCompletion(lc,"is_prime");
    }

}

int main(string[] args)
{
    auto prgname = args[0];
    writeln("Duketape console using d-duktape and linenoise");

    /* Parse options, with --multiline we enable multi line editing. */
    foreach (arg; args[1 .. $]) {
        if (arg == "--multiline") {
            linenoiseSetMultiLine(1);
            writeln("Multi-line mode enabled.");
        } else if (arg == "--keycodes") {
            linenoisePrintKeyCodes();
            return 0;
        } else {
            stderr.writefln("Usage: %s [--multiline] [--keycodes]", prgname);
            return 1;
        }
    }

    /* Set the completion callback. This will be called every time the
     * user uses the <tab> key. */
    linenoiseSetCompletionCallback(&completion);

    /* Load history from file. The history file is just a plain text file
     * where entries are separated by newlines. */
    linenoiseHistoryLoad("history.txt"); /* Load the history at startup */


	auto ctx = new DukContext();
    //duk_context *ctx = duk_create_heap_default();
    if (!ctx) {
        writeln("Failed to create a Duktape heap.");
        return 1;
    }
    duk_push_global_object(ctx._ctx);
    duk_print_alert_init(ctx._ctx, 0);

    // We register some functions in the global object to be used from javascript
  
	duk_push_c_function(ctx._ctx, &load, 1 /*nargs*/);
	duk_put_prop_string(ctx._ctx, -2, "load");
	
    // some functions written in D

    ctx.registerGlobal!is_prime;
    ctx.registerGlobal!print_many;

	while (true) 
	{
		char* line = linenoise(">");
		if (!line)
        	break; 	
        linenoiseHistoryAdd(line); /* Add to the history. */
        linenoiseHistorySave("history.txt"); /* Save the history on disk. */

		int ret = duk_peval_string(ctx._ctx, line);

        if (ret != 0) {
            writeln("Error: " ~ duk_to_string(ctx._ctx, -1).to!string);
        }
        else {
            if (!duk_is_undefined(ctx._ctx, -1))
                writeln(duk_to_string(ctx._ctx, -1).to!string);
        }
        
        duk_pop(ctx._ctx);

	} /* end of while loop */

	return 0;
}

