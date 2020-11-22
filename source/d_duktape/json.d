module d_duktape.json;

import std.conv;
import std.stdio;
import std.string;

import duktape;
import d_duktape.json;

//import vibe.data.serialization;
import vibe.data.json;


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
   default: writeln("Unhandled type in push_Json");
                assert(0);   
   } 
}

Json duk_to_Json(duk_context *ctx,  duk_idx_t idx)
{
  Json result;
  duk_int_t which_type = duk_get_type(ctx, idx);
  switch (which_type)
  {
    case DUK_TYPE_NULL:
          result=Json(null);
          break;

    case DUK_TYPE_BOOLEAN: 
          result=Json(duk_get_boolean(ctx, idx));
          break;   

    case DUK_TYPE_NUMBER: 
          result=Json(duk_get_number(ctx, idx));
          break;

    case DUK_TYPE_STRING:
          auto s=fromStringz(duk_get_string(ctx, idx));
          result= Json(to!string(s));
          break;

   case DUK_TYPE_OBJECT:
        writeln("Es un objeto");
        break;


   // the case bigInt is not supperted 
   default: writeln("Unhandled type in duk_to_Json ",which_type);
                assert(0);       
  }
  return result;
}
