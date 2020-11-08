/**
   This example shows how to construct a Duketape object from a vibe.d Json object
*/

// The modules to use duketape
import duktape;
import duk_extras.print_alert;
import d_duktape;


import std.stdio;
import std.string;
import std.conv;

import vibe.data.serialization;
import vibe.data.json;

struct MyStruct
{
  int int_data;
  string string_data;
  bool boolean_data;
  // you can mark some fields in your structure as optional
  // so that they are not requiered to appear in your Json data
  @optional int optional_data;
}

enum Direction { up, down, left, right }

static Json get_json()
{
  MyStruct other_data= MyStruct(5,"good bye!",true,4);
  Json other_json = serializeToJson(other_data);
  return other_json;
}

/* This function constructs a duktape object based on a vibe.d Json object */
void push_Json(duk_context *ctx,Json json)
{
   switch(json.type())
   {
     case Json.Type.int_: duk_push_int(ctx,to!int(json));
                         break;  
    case Json.Type.string: duk_push_string(ctx,to!string(json).toStringz());
                         break;      
    case Json.Type.bool_: duk_push_boolean(ctx,to!bool(json));
                         break;
    case Json.Type.float_: duk_push_number(ctx,to!double(json));
                         break;
    case Json.Type.null_: duk_push_null(ctx);
                         break;
    case Json.Type.undefined: duk_push_undefined(ctx);
                    break;
    case Json.Type.array: duk_idx_t arr_idx = duk_push_array(ctx);
                        int i=0;
                        foreach (value;json.byValue())
                        {
                          push_Json(ctx,value);
                          duk_put_prop_index(ctx, arr_idx, i);
                          i++;  
                        };               
                        break;
    case Json.Type.object: duk_idx_t obj_idx = duk_push_object(ctx);
                        foreach (key,value;json.byKeyValue)
                        {
                          push_Json(ctx,value);
                          duk_put_prop_string(ctx, obj_idx,key.toStringz());
                        };               
                        break;
   // the case bigInt is not supperted 
   default: writeln("Unhandled type in json");
                assert(0);   
   } 
}

extern (C) duk_ret_t int_example(duk_context *ctx) {
    Json json1 = serializeToJson(5);
    push_Json(ctx,json1);
    return 1; // we return something
}

extern (C) duk_ret_t string_example(duk_context *ctx) {
    Json json1 = serializeToJson("five");
    push_Json(ctx,json1);
    return 1; // we return something
}


extern (C) duk_ret_t boolean_example(duk_context *ctx) {
    Json json1 = serializeToJson(true);
    push_Json(ctx,json1);
    return 1; // we return something
}

extern (C) duk_ret_t float_example(duk_context *ctx) {
    Json json1 = serializeToJson(1.2);
    push_Json(ctx,json1);
    return 1; // we return something
}


extern (C) duk_ret_t null_example(duk_context *ctx) {
    Json json1 = serializeToJson(null);
    push_Json(ctx,json1);
    return 1; // we return something
}


extern (C) duk_ret_t undefined_example(duk_context *ctx) {
    Json json1 = Json.undefined();
    push_Json(ctx,json1);
    return 1; // we return something
}

extern (C) duk_ret_t array_example(duk_context *ctx) {
    Json[3] my_array= [Json(1),Json(2),Json(3)];
    Json json1 = Json(my_array);
    push_Json(ctx,json1);
    return 1; // we return something
}



extern (C) duk_ret_t array_example2(duk_context *ctx) {
    auto my_array1= [[1,2],[2,3]];
    Json json1 = serializeToJson(my_array1);
    push_Json(ctx,json1);
    return 1; // we return something
}


extern (C) duk_ret_t associative_array_example(duk_context *ctx) {
    int[string] dayNumbers =
    [ "Monday": 0, "Tuesday" : 1, "Wednesday" : 2,
    "Thursday" : 3, "Friday" : 4, "Saturday" : 5,
    "Sunday": 6 ];
    Json json1 = serializeToJson(dayNumbers);
    push_Json(ctx,json1);
    return 1; // we return something
}


void evaluate_js(duk_context *ctx,string line)
{
    int ret = duk_peval_string(ctx, line.toStringz());
    string  result = duk_to_string(ctx, -1).to!string;
    // writeln(result);
    //duk_pop(ctx);
}

int main()
{

    duk_context *ctx = duk_create_heap_default();
    if (!ctx) {
        writeln("Failed to create a Duktape heap.");
        return 1;
    }

    duk_push_global_object(ctx);
    duk_print_alert_init(ctx, 0);
    // We register a function in the global object to be used from javascript
    duk_push_c_function(ctx, &int_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "int_example");
    duk_push_c_function(ctx, &string_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "string_example");
    duk_push_c_function(ctx, &boolean_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "boolean_example");
    duk_push_c_function(ctx, &float_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "float_example");
    duk_push_c_function(ctx, &null_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "null_example");
    duk_push_c_function(ctx, &undefined_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "undefined_example");
    duk_push_c_function(ctx, &array_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "array_example");
    duk_push_c_function(ctx, &array_example2, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "array_example2");
    duk_push_c_function(ctx, &associative_array_example, 1 /*nargs*/);
    duk_put_prop_string(ctx, -2, "associative_array_example");
   
    
    evaluate_js(ctx,"var object = int_example(); print(object);");
    evaluate_js(ctx,"var object = string_example(); print(object);");
    evaluate_js(ctx,"var object = boolean_example(); print(object);");
    evaluate_js(ctx,"var object = float_example(); print(object);");
   
    evaluate_js(ctx,"var object = null_example(); print(object);");
    evaluate_js(ctx,"var object = undefined_example(); print(object);");

    evaluate_js(ctx,"var object = array_example(); print(object);");
    evaluate_js(ctx,"var object = array_example2(); print(JSON.stringify(object));");


    // print here does not give us what we want [[1,2],[2,3]] but 1,2,2,3
    evaluate_js(ctx,"var object = associative_array_example(); print(JSON.stringify(object));");
    
    // print(object) would give [object Object], something opaque 
    // It is better to use print(JSON.stringify(object)) when debugging javascript code!
 
    evaluate_js(ctx,"var object = associative_array_example(); print(object[\"Saturday\"]);");

    return 0;
}
