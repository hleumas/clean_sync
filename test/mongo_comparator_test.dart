library mongo_provider_test;

import "package:unittest/unittest.dart";
import "package:clean_sync/server.dart";
import "package:clean_sync/client.dart";
import "dart:async";

main() {
  MongoProvider collection;
  MongoDatabase mongodb;

  setup() {
    mongodb = new MongoDatabase('mongodb://0.0.0.0/mongoProviderTest');
    return Future.wait(mongodb.init)
    .then((_) => mongodb.dropCollection('sort_test'))
    .then((_) => mongodb.removeLocks())
    .then((_){
      collection = mongodb.collection('sort_test');
    });
  }

  Future _test(List<Map> input_to_sort, Map sort_params){
    Completer completer = new Completer();

    // sort with MongoComparator
    List<Map> given_output = new List.from(input_to_sort);
    given_output.sort((a,b) => MongoComparator.compare(a,b));

    // sort with MongoDb
    Future.forEach(input_to_sort, ((Map entry) => collection.add(entry, "test"))).then((_) {
      print("all was added");
      collection.find({}).sort(sort_params).data().then((Map data) {
        List<Map<String, dynamic>> expected_output = data['data'];
        print("expected_output: " + expected_output.toString().replaceAll("_id", "\n_id"));

        expect(expected_output.length, equals(given_output.length));

        // compare the two sortin methods
        for(int i=0; i<expected_output.length ; i++){

          // remove additional keys starting with _
          Map polished_map = {};
          expected_output[i].forEach((String key, value){
            if(!key.startsWith("_")){
              polished_map[key] = value;
            }
          });

          // compare
          expect(polished_map, equals(given_output[i]));
        }

        completer.complete(expected_output);
      });
    });

    return completer.future;
  };

  _teardown() {
    mongodb.close();
  };

  Future runTest(List<Map> input_to_sort, Map sort_params) {
    return setup()
      .then((_) => _test(input_to_sort, sort_params))
      .then((_) => _teardown());
  }

  test('Integer sorting.', () {
    List<Map> input_to_sort =
    [
      {'a' : 5},
      {'a' : 1},
      {'a' : 3},
      {'a' : 2},
      {'a' : 4},
    ];

    return runTest(input_to_sort, {'a' : 1});
  });
}