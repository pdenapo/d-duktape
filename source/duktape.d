/*
    D advanced binding for Duktape.

    It add automatic registration of D objects.
*/
import std.stdio;
import etc.c.duktape;


/** Advanced duk context. */
final class DukContext
{
    import std.traits;
    import std.conv : to;
    import std.string : toStringz, fromStringz;

private:
    duk_context *_ctx;
public:
    this()
    {
        _ctx = duk_create_heap_default;
    }

    ~this()
    {
        duk_destroy_heap(_ctx);
    }

    void evalString(string js)
    {
        duk_eval_string(_ctx, js.toStringz());
    }

    /// Automatic registration of D function.
    void registerFunction(alias Func)(string name = __traits(identifier, Func)) if (isFunction!Func)
    {
        auto externFunc = generateExternDukFunc!Func;
        duk_push_c_function(_ctx, externFunc, Parameters!Func.length /*nargs*/);
        duk_put_global_string(_ctx, name.toStringz());
    }

    T get(T)(int idx)
    {
        return dukGetType!T(_ctx, idx);
    }

    /// Utility method to get a type on the stack.
    private static T dukGetType(T)(duk_context *ctx, int idx)
    {
        static if (is(T == int))    return duk_get_int(ctx, idx);
        static if (is(T == bool))   return duk_get_boolean(ctx, idx);
        static if (is(T == float))  return duk_get_number(ctx, idx);
        static if (is(T == double)) return duk_get_number(ctx, idx);
        static if (is(T == string)) return fromStringz(duk_get_string(ctx, idx)).to!string;
    }

    /// Utility method to push a type on the stack.
    private static void dukPushType(T)(duk_context *ctx, T value)
    {
        static if (is(T == int))    duk_push_int(ctx, value);
        static if (is(T == bool))   duk_push_boolean(ctx, value);
        static if (is(T == float))  duk_push_number(ctx, value);
        static if (is(T == double)) duk_push_number(ctx, value);
        static if (is(T == string)) duk_push_string(ctx, value.toStringz());
    }

    auto generateExternDukFunc(alias Func)() if (isFunction!Func)
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            int n = duk_get_top(ctx);  // number of args

            // check parameter count
            if (n != Parameters!Func.length)
                return DUK_RET_RANGE_ERROR;

            // create a tuple of arguments
            Tuple!(Parameters!Func) args;
            static foreach(i, ArgType; Parameters!Func) {
                args[i] = dukGetType!ArgType(ctx, i);
            }

            // call the function
            if (is(ReturnType!Func == void)) {
                // TODO: handle void
            }
            else {
                ReturnType!Func ret = Func(args.expand);
                dukPushType(ctx, ret);
            }

            return 1; // one return value
        }

        return &func;
    }
}

///
unittest
{
    static int add(int a, int b) {
        return a + b;
    }

    auto ctx = new DukContext();
    ctx.registerFunction!add;

    ctx.evalString("add(1, 5)");
    assert(ctx.get!int(-1) == 6);
}

///
unittest
{
    static string capitalize(string s) {
        import std.string : capitalize;
        return s.capitalize();
    }

    auto ctx = new DukContext();
    ctx.registerFunction!capitalize;

    ctx.evalString(`capitalize("hEllO")`);
    assert(ctx.get!string(-1) == "Hello");
}