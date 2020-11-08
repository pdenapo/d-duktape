
// This example test json manipulations in duktape

// An object in Json
var text = '{ "usa_presidents" : [' +
'{ "firstName":"Gorge" , "lastName":"Washington" },' +
'{ "firstName":"John" , "lastName":"Adams" },' +
'{ "firstName":"Thomas" , "lastName":"Jefferson"} ]}';
// We convert to a Javascript object
var obj = JSON.parse(text);
var president = obj.usa_presidents[1]
print(president.firstName + " " + president.lastName);
// We convert it back to Json
print("In json:")
print(JSON.stringify(obj))