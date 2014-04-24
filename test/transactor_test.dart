library transactor_test;
import 'package:unittest/unittest.dart';
import 'package:clean_ajax/client.dart';
import 'package:mock/mock.dart';
import 'package:clean_sync/client.dart';
import 'package:clean_data/clean_data.dart';

class ConnectionMock extends Mock implements Connection {}
class IdGeneratorMock extends Mock implements IdGenerator {}

void main() {
  run();
}

void run() {
  group("Transactor", (){

    ConnectionMock connection;
    Transactor transactor;
    DataSet months;
    DataReference updateLock = new DataReference(null);
    bool failure;

    setUp(() {
      failure = false;
      connection = new ConnectionMock();
      transactor = new Transactor(connection, updateLock, 'author', new IdGeneratorMock());
      months = new DataSet()..addAll(
                ["jan","feb","mar","apr","jun","jul","aug","sep","oct","nov","dec"]);

      transactor.registerClientOperation("save",
        operation: (fullDocs, args, DataSet collection) {
          collection.add(args);
        }
      );
      transactor.registerClientOperation("change",
        operation: (fullDocs, args, DataSet collection) {
          if (fullDocs is List) fullDocs = fullDocs[0];
          args.forEach((k,v) => fullDocs[k] = v);
        }
      );
    });

    tearDown(() {
      months.clear();
    });

    test("transactor saves document", () {
      Map args = {"name":"random document"};
      return transactor.performOperation("save",
          args,
          collections: [months,'months']
      ).then((_) => expect(months.contains(args), isTrue));
    });

    test("transactor sends the right data", () {
      Map args = {"new" : "month"};
      List<Map> docs = [
          {"_id":"1", "haa":"ha", "__clean_collection":"weird"},
          {"_id":"2", "aee":"ug", "__clean_collection":"dummy"},
      ];
      return transactor.performOperation("change", {
        "collections" : [months,'months'],
        "docs" : docs,
        "args" : args
      }).then((_) =>
        expect(connection.getLogs(callsTo('send')).logs.first.args.first().toJson(),
            equals(new ClientRequest('sync-operation',{'operation':'change','args':{
              'docs':[['1','weird'],['2','dummy']],
              'collections':'months',
              'args':args}}).toJson()
            )
        )
      );
    });

  });
}