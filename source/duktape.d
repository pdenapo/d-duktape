import std.stdio;
import etc.c.duktape;


final class DukContext
{
    import std.traits;
    import std.string : toStringz;

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
        static if (is(T == int)) {
            return duk_get_int(ctx, idx);
        }
        else {
            static assert(false, T.stringof ~ " is not handled");
        }
    }

    /// Utility method to push a type on the stack.
    private static void dukPushType(T)(duk_context *ctx, T value)
    {
        static if (is(T == int)) {
            duk_push_int(ctx, value);
        }
        else {
            static assert(false, T.stringof ~ " is not handled");
        }
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
                args[i] = dukGetType!int(ctx, i);
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

unittest
{
    static int add(int a, int b) {
        return a + b;
    }

    auto ctx = new DukContext();
    ctx.registerFunction!add();

    ctx.evalString("add(1, 5)");
    assert(ctx.get!int(-1) == 6);
}
