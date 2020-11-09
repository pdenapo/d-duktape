/**
   This example shows how to construct a Duketape object from a vibe.d Json object
*/

// The modules to use duketape
import duktape;
import duk_extras.print_alert;
import d_duktape;
import  d_duktape.json;

import std.stdio;
import std.string;
import std.conv;

import vibe.data.json;

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

string evaluate_js(duk_context *ctx,string line)
{
    int ret = duk_peval_string(ctx, line.toStringz());
    string  result = duk_to_string(ctx, -1).to!string;
    // writeln(result);
    duk_pop(ctx);
    return result;
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
   
    const string days_in_json ="{\"Sunday\":6,\"Thursday\":3,\"Wednesday\":2,\"Saturday\":5,\"Tuesday\":1,\"Monday\":0,\"Friday\":4}";

    // print(object) would give [object Object], something opaque 
    // It is better to use print(JSON.stringify(object)) when debugging javascript code!
 
     auto test_cases = [ ["int_example()","5"],
                      ["string_example()","\"five\""],
                      ["boolean_example()","true"],
                      ["float_example()","1.2"],
                      ["null_example()","null"],
                      ["undefined_example()","undefined"],
                      ["JSON.stringify(array_example())","[1,2,3]"],
                      ["JSON.stringify(array_example2())","[[1,2],[2,3]]"],
                      ["JSON.stringify(associative_array_example())",days_in_json],
                      ["var object = associative_array_example(); object[\"Saturday\"]","5"]
                    ];

    bool all_passed=true;
    foreach (c;test_cases)
    {
      string result = evaluate_js(ctx,c[0]);
      bool test_passed = result==c[1];
      write(result,"\t");
      if (test_passed)
            writeln("TEST PASSED");
      else 
            writeln("TEST FAILED");
      all_passed = all_passed && test_passed;    
    }

    if (all_passed)
        writeln("All test passed.");
    else
        writeln("Some tests failed.");

    duk_destroy_heap(ctx);

    return 0;
}
