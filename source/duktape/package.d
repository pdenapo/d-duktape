/**
    D high level binding for Duktape.

    It add automatic registration of D symbol.
*/
module duktape;

import std.stdio;
import etc.c.duktape;
import std.string : toStringz, fromStringz;
import std.traits;

enum AllMembers(alias Symbol) = __traits(allMembers, Symbol);
enum Protection(alias Symbol) = __traits(getProtection, Symbol);
enum Identifier(alias Symbol) = __traits(identifier, Symbol);

static bool IsPublic(alias Symbol)() { return Protection!Symbol == "public"; }


class DukContextException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}


/** Advanced duk context.

It allow to register D symbol directly.
*/
final class DukContext
{
    import std.conv : to;
    import std.typecons;

private:
    static immutable char* CLASS_DATA_PROP ; /// "\xFF" mean to hide property
    static immutable char* CLASS_DELETED_PROP;
    @property duk_context* raw() { return _ctx; }

public:
    duk_context *_ctx;
    shared static this()
    {
        CLASS_DATA_PROP = ("\xFF\xFF" ~ "objPtr").toStringz();
        CLASS_DELETED_PROP = ("\xFF\xFF" ~ "objDel").toStringz();
    }

    this()
    {
        //_ctx = duk_create_heap_default;
        _ctx = duk_create_heap(null, null, null, null, &my_fatal);
    }

    extern (C) static void my_fatal(void *udata, const char *msg)
    {
        /* Note that 'msg' may be NULL. */
        throw new DukContextException(fromStringz(msg).to!string);
    }

    ~this()
    {
        duk_destroy_heap(_ctx);
    }

    /** Evaluate a JS string and get an optional result
        Params:
            js = the source code
    */
    T evalString(T=void)(string js)
    {
        duk_eval_string(_ctx, js.toStringz());

        static if (!is(T == void))
            return get!T();
    }

    ///
    unittest
    {
        auto ctx = new DukContext();
        ctx.evalString("a = 42;");
        assert(ctx.evalString!int("a = 1 + 2") == 3);
    }

    /** Register a global object in JS context. */
    DukContext registerGlobal(alias Symbol)(string name = Identifier!Symbol)
    {
        register!Symbol();
        duk_put_global_string(_ctx, name.toStringz());
        return this;
    }

    /// Set a previously registered symbol as global.
    DukContext setGlobal(string name)
    {
        duk_put_global_string(_ctx, name.toStringz());
        return this;
    }

    ///
    unittest
    {
        static int add(int a, int b) {
            return a + b;
        }

        auto ctx = new DukContext();
        ctx.registerGlobal!add;

        auto res = ctx.evalString!int("add(1, 5)");
        assert(res == 6);
    }

    /// Automatic registration of D function. (not global)
    DukContext register(alias Func)() if (isFunction!Func)
    {
        auto externFunc = generateExternDukFunc!Func;
        duk_push_c_function(_ctx, externFunc, Parameters!Func.length /*nargs*/);
        return this;
    }

    ///
    unittest
    {
        static int square(int n) { return n*n; }

        auto ctx = new DukContext();
        ctx.register!square.setGlobal("square"); // equivalent to ctx.registerGlobal!square
        assert(ctx.evalString!int(r"a = square(5)") == 25);
    }

    /// Automatic registration of D enum. (not global)
    DukContext register(alias Enum)() if (is(Enum == enum))
    {
        alias EnumBaseType = OriginalType!Enum;

        duk_idx_t arr_idx;
        arr_idx = duk_push_array(_ctx);

        // push a js array
        static foreach(Member; EnumMembers!Enum) {
            this.push!EnumBaseType(_ctx, cast(EnumBaseType) Member); // push value
            duk_put_prop_string(_ctx, arr_idx, to!string(Member).toStringz()); // push string prop
        }
        return this;
    }

    ///
    unittest
    {
        enum Direction { up = 0, down = 1 }

        auto ctx = new DukContext();
        ctx.register!Direction.setGlobal("Direction"); // equivalent to ctx.registerGlobal!Direction
        assert(ctx.evalString!int(r"a = Direction.down") == 1);
    }

    /// Automatic registration of D class. (not global)
    DukContext register(alias Class)() if (is(Class == class))
    {
        import std.algorithm: canFind;

        enum MemberToIgnore = [
            "__ctor", "__dtor", "this",
            "__xdtor", "toHash", "opCmp",
            "opEquals", "Monitor", "factory",
        ];
        enum Members = AllMembers!Class;

        // create constructor function
        auto dukContructor = this.generateExternDukConstructor!Class;
        duk_push_c_function(_ctx, dukContructor,
            Parameters!(__traits(getMember, Class.init, "__ctor")).length);

        /* Push MyObject.prototype object. */
        int objIdx = duk_push_object(_ctx);

        Class base;
        uint propFlags = 0;
        // push prototype methods
        static foreach(Method; Members) {
            // Error: class foo.Foo member x is not accessible workaround
            static if (is(typeof(__traits(getMember, Class.init, Method)))) {
                static if (IsPublic!(__traits(getMember, base, Method)) && !MemberToIgnore.canFind(Method)) {
                    static if (isFunction!(__traits(getMember, base, Method))) {
                        // it is a property and exclude toString
                        static if (hasFunctionAttributes!(__traits(getMember, Class.init, Method), "@property") &&
                                (Method.stringof !is "toString")) {
                            // iterate property overloads
                            push!string(Identifier!(__traits(getMember, Class.init, Method)));  // [... key]
                            propFlags = DUK_DEFPROP_FORCE | DUK_DEFPROP_HAVE_CONFIGURABLE;

                            // the getter must be registered first
                            static foreach(GetterSetter; __traits(getOverloads, Class, Method)) {
                                // its a getter
                                static if (Parameters!GetterSetter.length is 0) {
                                    duk_push_c_function(_ctx,
                                        generateExternDukMethod!(Class, GetterSetter),
                                        Parameters!(GetterSetter).length ); // [obj key get]
                                    propFlags |= DUK_DEFPROP_HAVE_GETTER;
                                }
                            }

                            // try to register a setter
                            static foreach(GetterSetter; __traits(getOverloads, Class, Method)) {
                                // its a setter
                                static if (Parameters!GetterSetter.length !is 0) {
                                    duk_push_c_function(_ctx,
                                        generateExternDukMethod!(Class, GetterSetter),
                                        Parameters!(GetterSetter).length ); // [obj key get]
                                    propFlags |= DUK_DEFPROP_HAVE_SETTER;
                                }
                            }
                            duk_def_prop(_ctx, objIdx, propFlags); // [obj]
                        }
                        else {
                            duk_push_c_function(_ctx,
                                generateExternDukMethod!(Class, __traits(getMember, Class.init, Method)),
                                Parameters!(__traits(getMember, Class.init, Method)).length /*nargs*/); // [obj func]
                            duk_put_prop_string(_ctx, objIdx, Method); // [obj func]
                        }
                    }
                }
            }
        }

         /* Set MyObject.prototype = proto */
        duk_put_prop_string(_ctx, objIdx - 1, "prototype");

        return this;
    }

    ///
    unittest
    {
        // Point is a class that hold x, y coordinates
        auto ctx = new DukContext();
        ctx.register!Point.setGlobal("Point"); // equivalent to ctx.registerGlobal!Point
        assert(ctx.evalString!string(r"new Point(1, 2).toString()") == "(1, 2)");
    }

    /** Open a new JS namespace.
    You can then register symbol inside and call finalize() when
    its done.
    */
    NamespaceContext createNamespace(string name)
    {
        return new NamespaceContext(this, name);
    }

    ///
    unittest
    {
        enum Direction { up, down }

        auto ctx = new DukContext();

        ctx.createNamespace("Com")
            .register!Direction
            .finalize();

        assert(ctx.evalString!int("Com.Direction.down") == 1);
    }


    /// Get a value on the stack.
    T get(T)(int idx = -1)
    {
        return get!T(_ctx, idx);
    }

    ///
    unittest
    {
        auto ctx = new DukContext();

        ctx.push([1, 2, 3]);

        assert([1, 2, 3] == ctx.get!(int[]));
    }

    void push(T)(T value)
    {
        return push!T(_ctx, value);
    }

private:
    /// Utility method to push a type on the stack.
    static void push(T)(duk_context *ctx, T value)
    {
        static if (is(T == int))         duk_push_int(ctx, value);
        else static if (is(T == bool))   duk_push_boolean(ctx, value);
        else static if (is(T == float))  duk_push_number(ctx, value);
        else static if (is(T == double)) duk_push_number(ctx, value);
        else static if (is(T == string)) duk_push_string(ctx, value.toStringz());
        else static if (is(T == enum))   push!(OriginalType!T)(ctx, cast(OriginalType!T) value);
        else static if (is(T == class)) {
            // Store the underlying object
            duk_push_pointer(ctx, cast(void*) value);
            duk_put_prop_string(ctx, -2, CLASS_DATA_PROP);

            // Store a boolean flag to mark the object as deleted because the destructor may be called several times
            duk_push_boolean(ctx, false);
            duk_put_prop_string(ctx, -2, CLASS_DELETED_PROP);

        }
        else static if (isArray!T) {
            alias Elem = ForeachType!T;
            auto arrIdx = duk_push_array(ctx);

            foreach(uint i, Elem elem; value) {
                push!Elem(ctx, elem);
                duk_put_prop_index(ctx, arrIdx, i);
            }
        }
        else {
            static assert(false, T.stringof ~ " argument is not handled.");
        }
    }

    /// Utility method to get a type on the stack.
    static T get(T)(duk_context *ctx, int idx = -1)
    {
        static if (is(T == int))    return duk_require_int(ctx, idx);
        else static if (is(T == bool))   return duk_require_boolean(ctx, idx);
        else static if (is(T == float))  return duk_require_number(ctx, idx);
        else static if (is(T == double)) return duk_require_number(ctx, idx);
        else static if (is(T == string)) return fromStringz(duk_require_string(ctx, idx)).to!string;
        else static if (is(T == enum))   return cast(T) get!(OriginalType!T)(ctx, idx); // get enum base type
        else static if (is(T == class)) {
            if (!duk_is_object(ctx, idx))
                duk_error(ctx, DUK_ERR_TYPE_ERROR, "expected an object");

            duk_get_prop_string(ctx, idx, CLASS_DATA_PROP);
            void* addr = duk_get_pointer(ctx, -1);
            duk_pop(ctx);  // pop CLASS_DATA_PROP
            return cast(T) addr;
        }
        else static if (isArray!T) {
            if (!duk_is_array(ctx, idx))
                duk_error(ctx, DUK_ERR_TYPE_ERROR, "expected an array of " ~ ForeachType!T.stringof);

            T result;
            ulong length = duk_get_length(ctx, idx);
            for (int i = 0; i < length; i++) {
                duk_get_prop_index(ctx, idx, i);
                result ~= get!(ForeachType!T)(ctx, -1); // recursion on array element type
                duk_pop(ctx); // duk_get_prop_index
            }

            return result;
        }
        else static if (is(T == delegate)) {
            // build a delegate englobing duk call
            return (Parameters!T args) {
                duk_require_function(ctx, idx); // [... func ...]
                duk_dup(ctx, idx); // [... func ... func]

                // prepare for a duk_call
                static foreach(i, PT; Parameters!T)
                    push!PT(ctx, args[i]); // [... func ... func arg1 argN ...]

                duk_call(ctx, Parameters!T.length); // [... func ... func retval]
                static if (is(ReturnType!T == void))
                    duk_pop_2(ctx);
                else {
                    auto result = get!(ReturnType!T)(ctx, -1);
                    duk_pop_2(ctx);
                    return result;
                }
            };
        }
        else {
            static assert(false, T.stringof ~ " argument is not handled.");
        }
    }

    /** Get all function arguments on the stask.
    Params:
        ctx = duk context
    Template_Params:
        Func = the func
    Returns: A tuple of arguments.
    */
    static auto getArgs(alias Func)(duk_context *ctx) if (isFunction!Func)
    {
        Tuple!(Parameters!Func) args;
        static foreach(i, ArgType; Parameters!Func) {
            args[i] = get!ArgType(ctx, i);
        }
        return args;
    }

    /** Call the function with a tuple of arguments.
        Returns: the number of return valuee
    */
    static int call(alias Func)(duk_context *ctx, Tuple!(Parameters!Func) args) if (isFunction!Func)
    {
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

    /** Call the method with a tuple of arguments.
        Returns: the number of return valuee
    */
    static int callMethod(alias Method, T)(duk_context *ctx, Tuple!(Parameters!Method) args, T instance) if (isFunction!Method)
    {
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

    auto generateExternDukFunc(alias Func)() if (isFunction!Func)
    {
        extern(C) static duk_ret_t func(duk_context *ctx) {
            int n = duk_get_top(ctx);  // [arg1 argN ...]
            // check parameter count
            if (n != Parameters!Func.length)
                return DUK_RET_RANGE_ERROR;

            auto args = getArgs!Func(ctx);
            return call!Func(ctx, args);
        }

        return &func;
    }

    auto generateExternDukMethod(alias Class, alias Method)() if (is(Class == class) && isFunction!Method)
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            duk_push_this(ctx); // [this]
            duk_get_prop_string(ctx, -1, CLASS_DATA_PROP); // [this val]
            void* addr = duk_get_pointer(ctx, -1);
            duk_pop_2(ctx); // []
            Class instance = cast(Class) addr;

            int n = duk_get_top(ctx);  // number of args

            // check parameter count
            if (n != Parameters!Method.length)
                return DUK_RET_RANGE_ERROR;

            auto args = getArgs!Method(ctx);
            duk_pop_n(ctx, n);
            return callMethod!Method(ctx, args, instance);
        }

        return &func;
    }

    auto generateExternDukConstructor(alias Class)() if (is(Class == class))
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            if (!duk_is_constructor_call(ctx)) {
                return DUK_RET_TYPE_ERROR;
            }

            // must have a constructor
            static assert(hasMember!(Class, "__ctor"), Class.stringof ~ ": a constructor is required.");

            // check constructor parameter count
            int n = duk_get_top(ctx);  // [arg1 argn ...]
            if (n != Parameters!(__traits(getMember, Class.init, "__ctor")).length)
                return DUK_RET_RANGE_ERROR;

            auto args = getArgs!(__traits(getMember, Class.init, "__ctor"))(ctx);
            duk_pop_n(ctx, n);

            // Push special this binding to the function being constructed
            duk_push_this(ctx); // [this]

            // instanciate class @nogc
            // lifetime is managed by j
            auto instance = new Class(args.expand);

            // Store the underlying object
            duk_push_pointer(ctx, cast(void*) instance); // [this ptr]
            duk_put_prop_string(ctx, -2, CLASS_DATA_PROP); // [this]

            // Store a boolean flag to mark the object as deleted because the destructor may be called several times
            duk_push_boolean(ctx, false); // [this bool]
            duk_put_prop_string(ctx, -2, CLASS_DELETED_PROP); // [this]

            auto classDestructor = generateExternDukDestructor!Class(ctx);

            // Store the function destructor
            duk_push_c_function(ctx, classDestructor, 1); // [this func]
            duk_set_finalizer(ctx, -2); // [this]

            duk_pop(ctx); // pop this

            return 0;
        }

        return &func;
    }

    static auto generateExternDukDestructor(alias Class)(duk_context *ctx) if (is(Class == class))
    {
        import std.typecons;

        extern(C) static duk_ret_t func(duk_context *ctx) {
            // The object to delete is passed as first argument instead
            duk_get_prop_string(ctx, 0, CLASS_DELETED_PROP); // [obj val]

            bool deleted = (duk_to_boolean(ctx, -1) != 0);
            duk_pop(ctx); // [obj]

            if (!deleted) {
                auto str = CLASS_DATA_PROP;

                duk_get_prop_string(ctx, 0, CLASS_DATA_PROP); // [obj val]
                void* addr = duk_to_pointer(ctx, -1); // [obj val]
                duk_pop(ctx); // [obj]

                Class instance = cast(Class) addr;
                destroy(instance);

                // Mark as deleted
                duk_push_boolean(ctx, true); // [obj bool]
                duk_put_prop_string(ctx, 0, CLASS_DELETED_PROP); // [obj]
            }

            duk_pop(ctx);

            return 0;
        }

        return &func;
    }
}

///
unittest
{
    static Point add(Point a, Point b) {
        return new Point(a.x + b.x, a.y + b.y);
    }

    enum Directions { up, down }

    auto ctx = new DukContext();
    ctx.registerGlobal!add;
    ctx.registerGlobal!Directions;
    ctx.registerGlobal!Point;


    assert(ctx.evalString!string(q"{
        p1 = new Point(20, 40);
        p2 = new Point(10, 20);
        p3 = add(p1, p2);

        p3.toString();
    }") == "(30, 60)");
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
        _ctx.register!Symbol();
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
    enum Direction
    {
        up,
        down
    }

    auto ctx = new DukContext();

    ctx.createNamespace("Work")
        .register!Direction
        .finalize();

    auto res = ctx.evalString!int("Work.Direction.down");
    assert(res == 1);
}

version (unittest)
{
    class Foo {}

    class Point
    {
        float _x;
        float _y;

        @property float x() { return _x; }
        @property void x(float v) { _x = v; }
        @property float y() { return _y; }
        @property void y(float v) { _y = v; }

        this(float x, float y)
        {
            this._x = x;
            this._y = y;
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
}

// Class: must have a constructor
unittest
{
    auto ctx = new DukContext();
    assert(!__traits(compiles, ctx.registerGlobal!Foo));
}

//
unittest
{
    static string capitalize(string s) {
        import std.string : capitalize;
        return s.capitalize();
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!capitalize;

    auto res = ctx.evalString!string(`capitalize("hEllO")`);
    assert(res == "Hello");
}

// register!Enum
unittest
{
    enum Direction
    {
        up,
        down
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!Direction;

    auto res = ctx.evalString!int("Direction['up']");
    assert(res == 0);

    res = ctx.evalString!int("Direction['down']");
    assert(res == 1);
}

// class
unittest
{
    static void inc(Point p) {
        p.x = p.x + 1;
        p.y = p.y + 1;
    }

    static void incArray(Point[] pts) {
        foreach(p; pts) inc(p);
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!Point;
    ctx.registerGlobal!inc;
    ctx.registerGlobal!incArray;

    auto res = ctx.evalString!string(q"{
        p1 = new Point(20, 40);
        p2 = new Point(10, 20);
        p2.toString();
        inc(p2);
        p2.toString();
    }");
    assert(res == "(11, 21)");

    res = ctx.evalString!string(q"{
        arr = [new Point(0, 1), new Point(2, 3)];
        incArray(arr);
        arr[1].toString();
    }");
    assert(res == "(3, 4)");
}

// class properties
unittest
{

    auto ctx = new DukContext();
    ctx.registerGlobal!Point;

    auto res = ctx.evalString!int(q"{
        p = new Point(45, 96);
        p.x = 12;
        p.y = 26
        a = p.x + p.y
    }");
    assert(res == 12 + 26);
}

// arrays
unittest
{
    static T[] sort(T)(T[] arr) {
        import std.algorithm.sorting : sort;
        return arr.sort().release();
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!(sort!int);

    auto res = ctx.evalString!(int[])("sort([5, 1, 3])");
    assert(res == [1, 3, 5]);
}

// callable arguments
unittest
{
    alias Callable = int delegate(int, int);
    static int callWith(Callable callable, int a1, int a2) {
        return callable(a1, a2);
    }

    auto ctx = new DukContext();
    ctx.registerGlobal!callWith;

    auto res = ctx.evalString!int(q"{
        callWith(function(a, b) {return a+b; }, 1, 2);
    }");
    assert(res == 3);
}