/**
   This example shows that a function returning Json is automatically wrapped
   to a javascript function returning an object
*/

import d_duktape;
//import  d_duktape.json;

import std.stdio;
import std.string;
import std.conv;
import duk_extras.print_alert;

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

static Json get_json()
{
  MyStruct my_data= MyStruct(5,"good bye!",true,4);
  Json my_json = serializeToJson(my_data);
  return my_json;
}

static string put_json(Json my_json)
{
  MyStruct my_data =  deserializeJson!MyStruct(my_json);
  return my_data.string_data;
}


int main()
{
    auto ctx = new DukContext();
    duk_print_alert_init(ctx._ctx, 0);

    ctx.registerGlobal!get_json;
    ctx.registerGlobal!put_json;

    ctx.evalString("var object=get_json();print(JSON.stringify(object));print(object.string_data);");

    return 0;
}

