/*
    D advanced binding for Duktape.

    It add automatic registration of D objects.
*/
import std.stdio;
import etc.c.duktape;
import std.string : toStringz, fromStringz;
import std.traits;

enum AllMembers(alias Symbol) = __traits(allMembers, Symbol);
enum Protection(alias Symbol) = __traits(getProtection, Symbol);
enum Member(alias Symbol, string n) = __traits(getMember, Symbol, n);
enum Identifier(alias Symbol) = __traits(identifier, Symbol);

static bool IsPublic(alias Symbol)() { return Protection!Symbol == "public"; }

/** Advanced duk context. */
final class DukContext
{
    import std.conv : to;

private:
    duk_context *_ctx;

    @property duk_context* raw() { return _ctx; }

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

    DukContext registerGlobal(alias Symbol)(string name = Identifier!Symbol)
    {
        register!Symbol(name);
        duk_put_global_string(_ctx, name.toStringz());
        return this;
    }

    /// Automatic registration of D function.
    DukContext register(alias Func)(string name = Identifier!Func) if (isFunction!Func)
    {
        auto externFunc = generateExternDukFunc!Func;
        duk_push_c_function(_ctx, externFunc, Parameters!Func.length /*nargs*/);
        return this;
    }

    /// Automatic registration of D enum.
    DukContext register(alias Enum)(string name = Identifier!Enum) if (is(Enum == enum))
    {
        alias EnumBaseType = OriginalType!Enum;

        duk_idx_t arr_idx;
        arr_idx = duk_push_array(_ctx);

        // push a js array
        static foreach(Member; [EnumMembers!Enum]) {
            this.push!EnumBaseType(_ctx, cast(EnumBaseType) Member); // push value
            duk_put_prop_string(_ctx, arr_idx, to!string(Member).toStringz()); // push string prop
        }
        return this;
    }

    /// Automatic registration of D class.
    DukContext register(alias Class)(string name = Identifier!Class) if (is(Class == class))
    {
        import std.algorithm: canFind;

        enum MemberToIgnore = [
            "__ctor", "__dtor", "this",
            "__xdtor", "toHash", "opCmp",
            "opEquals", "Monitor", "factory",
        ];
        enum Members = AllMembers!Class;

        //duk_idx_t obj_idx;
        //obj_idx = duk_push_object(_ctx);

        // create constructor function
        auto dukContructor = this.generateExternDukConstructor!Class;
        duk_push_c_function(_ctx, dukContructor,
            Parameters!(__traits(getMember, Class.init, "__ctor")).length);

        /* Push MyObject.prototype object. */
        duk_push_object(_ctx);

        Class base;
        // push prototype methods
        static foreach(Method; Members) {
            static if (IsPublic!Method && !MemberToIgnore.canFind(Method)) {
                static if (isFunction!(__traits(getMember, base, Method))) {
                    // pragma(msg, Parameters!(__traits(getMember, Class.init, Method)));

                    duk_push_c_function(_ctx,
                        generateExternDukMethod!(Class, __traits(getMember, Class.init, Method)),
                        Parameters!(__traits(getMember, Class.init, Method)).length /*nargs*/);
                    duk_put_prop_string(_ctx, -2, Method);
                }
            }
        }

         /* Set MyObject.prototype = proto */
        duk_put_prop_string(_ctx, -2, "prototype");

/*
        // Create a prototype with toString and all other functions
        duk_push_object(ctx);
        duk_put_function_list(ctx, -1, methods);
        duk_put_prop_string(ctx, -2, "prototype");

        // Now store the Point function as a global
        duk_put_global_string(ctx, "Point");

        if (duk_peval_string(ctx, "p = new Point(20, 40); print(p)") != 0) {
            std::cerr << "error: " << duk_to_string(ctx, -1) << std::endl;
            std::exit(1);
        }
        */

        static foreach (mem; __traits(allMembers, Class))
        {
            static if (mem != "this")
            {

            }
        }
        // https://wiki.duktape.org/HowtoNativeConstructor.html
        // register methods


        return this;
    }

    NamespaceContext createNamespace(string name)
    {
        return new NamespaceContext(this, name);
    }

    T get(T)(int idx = -1)
    {
        return get!T(_ctx, idx);
    }

    /// Utility method to get a type on the stack.
    private static T get(T)(duk_context *ctx, int idx)
    {
        static if (is(T == int))    return duk_get_int(ctx, idx);
        static if (is(T == bool))   return duk_get_boolean(ctx, idx);
        static if (is(T == float))  return duk_get_number(ctx, idx);
        static if (is(T == double)) return duk_get_number(ctx, idx);
        static if (is(T == string)) return fromStringz(duk_get_string(ctx, idx)).to!string;
    }

    /// Utility method to push a type on the stack.
    private static void push(T)(duk_context *ctx, T value)
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
                args[i] = get!ArgType(ctx, i);
            }

            // call the function
            static if (is(ReturnType!Func == void)) {
                Func(args.expand);
                return 0;
            }
            else {
                ReturnType!Func ret = Func(args.expand);
                push(ctx, ret);
                return 1; // one return value
            }
        }

        return &func;
    }

    auto generateExternDukMethod(alias Class, alias Method)() if (is(Class == class) && isFunction!Method)
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            duk_push_this(ctx);
            duk_get_prop_string(ctx, -1, "___data___");
            void* addr = duk_to_pointer(ctx, -1);
            duk_pop(ctx);
            duk_pop(ctx); // deleted

            Class instance = cast(Class) addr;

            int n = duk_get_top(ctx);  // number of args

            // check parameter count
            if (n != Parameters!Method.length)
                return DUK_RET_RANGE_ERROR;

            // create a tuple of arguments
            Tuple!(Parameters!Method) args;
            static foreach(i, ArgType; Parameters!Method) {
                args[i] = get!ArgType(ctx, i);
            }

            // call the method
            static if (is(ReturnType!Method == void)) {
                __traits(getMember, instance, Identifier!Method)(args.expand);
                return 0;
            }
            else {
                ReturnType!Method ret = __traits(getMember, instance, Identifier!Method)(args.expand);
                push(ctx, ret);
                return 1; // one return value
            }
        }

        return &func;
    }

    auto generateExternDukConstructor(alias Class)() if (is(Class == class))
    {
        import std.typecons;
        import core.memory;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            if (!duk_is_constructor_call(ctx)) {
                return DUK_RET_TYPE_ERROR;
            }

            // check constructor parameter count
            int n = duk_get_top(ctx);  // number of args
            if (n != Parameters!(__traits(getMember, Class.init, "__ctor")).length)
                return DUK_RET_RANGE_ERROR;

            // create a tuple of arguments
            Tuple!(Parameters!(__traits(getMember, Class.init, "__ctor"))) args;
            static foreach(i, ArgType; Parameters!(__traits(getMember, Class.init, "__ctor"))) {
                args[i] = get!ArgType(ctx, i);
            }

            // Push special this binding to the function being constructed
            duk_push_this(ctx);

            // instanciate class @nogc
            // lifetime is managed by j
            auto instance = new Class(args.expand);
            GC.removeRoot(cast(void*) instance);

            // Store the underlying object
            duk_push_pointer(ctx, cast(void*) instance);
            duk_put_prop_string(ctx, -2, "___data___");

            // Store a boolean flag to mark the object as deleted because the destructor may be called several times
            duk_push_boolean(ctx, false);
            duk_put_prop_string(ctx, -2, "___deleted___");

            auto classDestructor = generateExternDukDestructor!Class(ctx);

            // Store the function destructor
            duk_push_c_function(ctx, classDestructor, 1);
            duk_set_finalizer(ctx, -2);

            return 0;
        }

        return &func;
    }

    static auto generateExternDukDestructor(alias Class)(duk_context *ctx) if (is(Class == class))
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            // The object to delete is passed as first argument instead
            duk_get_prop_string(ctx, 0, "___deleted___");

            bool deleted = (duk_to_boolean(ctx, -1) != 0);
            duk_pop(ctx);

            if (!deleted) {
                duk_get_prop_string(ctx, 0, "___data___");
                void* addr = duk_to_pointer(ctx, -1);
                duk_pop(ctx);

                Class instance = cast(Class) addr;
                destroy(instance);

                // Mark as deleted
                duk_push_boolean(ctx, true);
                duk_put_prop_string(ctx, 0, "___deleted___");
            }

            return 0;
        }

        return &func;
    }
}

/// Namespace support
final class NamespaceContext
{
private:
    DukContext _ctx;
    string _name;
    duk_idx_t _arrIdx;
    bool _finalized = false;

public:
    this(DukContext ctx, string name)
    {
        _ctx = ctx;
        _name = name;

        // a namespace is a js array
        _arrIdx = duk_push_array(_ctx.raw);
    }

    ~this()
    {
        if (!_finalized)
            finalize();
    }

    NamespaceContext register(alias Symbol)(string name = Identifier!Symbol)
    {
        _ctx.register!Symbol(name);
        duk_put_prop_string(_ctx.raw, _arrIdx, name.toStringz()); // push string prop
        return this;
    }

    void finalize()
    {
        duk_put_global_string(_ctx.raw, _name.toStringz());
        _finalized = true;
    }
}

///
unittest
{
    static int add(int a, int b) {
        return a + b;
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!add;

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
    ctx.registerGlobal!capitalize;

    ctx.evalString(`capitalize("hEllO")`);
    assert(ctx.get!string(-1) == "Hello");
}

/// register!Enum
unittest
{
    enum Direction
    {
        up,
        down
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!Direction;

    ctx.evalString("Direction['up']");
    assert(ctx.get!int() == 0);

    ctx.evalString("Direction['down']");
    assert(ctx.get!int() == 1);
}

/// namespace
unittest
{
    enum Direction
    {
        up,
        down
    }

    auto ctx = new DukContext();

    ctx.createNamespace("Work")
        .register!Direction
        .finalize();

    ctx.evalString("Work.Direction.down");
    assert(ctx.get!int() == 1);
}

class Point
{
    float x;
    float y;

    this(float x, float y)
    {
        this.x = x;
        this.y = y;
    }

    ~this()
    {
    }

    override string toString()
    {
        import std.conv : to;
        return "(" ~ to!string(x) ~ ", " ~ to!string(y) ~ ")";
    }
}

/// class
unittest
{
    auto ctx = new DukContext();
    ctx.registerGlobal!Point;

    ctx.evalString("p = new Point(20, 40); p.toString()");
    assert(ctx.get!string() == "(20, 40)");
}
