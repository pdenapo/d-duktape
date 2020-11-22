/**
  Now we want to go from a javascript object o a Json structure.
*/

import d_duktape;
import duktape;
import duk_extras.print_alert;
import  d_duktape.json;


import std.stdio;
import std.string;
import std.conv;
import duk_extras.print_alert;

import vibe.data.json;

string evaluate_js(duk_context *ctx,string line)
{
    int ret = duk_peval_string(ctx, line.toStringz());
    string  result = duk_to_string(ctx, -1).to!string;
//    duk_pop(ctx);
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

    // Lista de casos para testear
    // comando en Js y su representación en D

     auto test_cases = [["1;","1"],
                       ["\"hola\"","hola"],
                       ["1==2","false"],
                       ["null","null"]];


         bool all_passed=true;
    foreach (c;test_cases)
    {
      evaluate_js(ctx,c[0]);
      Json result = duk_to_Json(ctx,-1);

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