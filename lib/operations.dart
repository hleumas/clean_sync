import 'package:clean_sync/server.dart';
import 'package:clean_sync/mongo_server.dart';
import 'package:clean_data/clean_data.dart';
import 'package:logging/logging.dart';


class ValidationException implements Exception {
  final String error;
  final String stackTrace;
  ValidationException(this.error, [this.stackTrace]);
  String toString() => error;
}

Logger logger = new Logger('mongo_wrapper_logger');


class ServerOperation {
  String name;
  List<Function> _before = [];
  Function operation;
  List<Function> _after = [];

  List<Function> get before {
    if (_before == null) _before = [];
    return _before;
  }

  List<Function> get after {
    if (_after == null) _after = [];
    return _after;
  }

  ServerOperation(this.name, {before, this.operation, after}) {
    _before = before != null ? [before] : [];
    _after = after != null ? [after] : [];
  }

  ClientOperation toClientOperation() =>
      new ClientOperation(this.name, operation:this.operation);
}

class ClientOperation {
  String name;
  Function operation;
  List<Function> _argsDecorator = [];

  List<Function> get argsDecorator {
    if (_argsDecorator == null) _argsDecorator = [];
    return _argsDecorator;
  }

  ClientOperation(this.name, {this.operation});
}

// First element is ServerOperation, second is equivalent ClientOperation
List<List> incompatibleOperations = [
  [
    new ServerOperation('add',
      before: (ServerOperationCall opCall) {
        if (!opCall.args.containsKey("_id")) throw new ValidationException("Document does not contain _id");

        return opCall.colls[0].find({"_id": opCall.args["_id"]}).data()
            .then((data){
               if(data['data'].length > 0) {
                 throw new ValidationException("_id given is already used");
               }
            })
        .catchError((e,s) {
          if (e is ValidationException) throw e;
        });
      },

      operation: (ServerOperationCall opCall) {
        return opCall.colls[0].add(opCall.args, '');
      }),

    new ClientOperation('add',
      operation: (ServerOperationCall opCall) {
        opCall.colls[0].add(opCall.args, '');
      })
  ],
  [
    new ServerOperation('remove',
      before: (ServerOperationCall opCall) {
        if (!opCall.args.containsKey("_id")) throw new ValidationException("Args should contain _id");
        return opCall.colls[0].find({"_id": opCall.args["_id"]}).findOne()
            .catchError((e,s) =>
                // Find one threw => there are no entries with given _id
          throw new ValidationException("No document with given _id found"));

      },
      operation: (ServerOperationCall opCall) {
        return opCall.colls[0].remove(opCall.args["_id"], "");
      }),

    new ClientOperation('remove',
      operation: (ServerOperationCall opCall){
        opCall.colls[0].remove(opCall.args["_id"], "");
      })
  ],

  [
    new ServerOperation('addAll',
      operation: (ServerOperationCall opCall) {
        return opCall.colls[0].addAll(opCall.args["data"], "");
      }),

    new ClientOperation('addAll',
      operation: (ServerOperationCall opCall){
        opCall.colls[0].addAll(opCall.args["data"], "");
      })
  ],

  [
    new ServerOperation('removeAll',
      operation: (ServerOperationCall opCall) {
        return opCall.colls[0].removeAll({'_id': {'\$in': opCall.args['ids']}}, "");
      }),

    new ClientOperation('removeAll',
      operation: (ServerOperationCall opCall){
        opCall.colls[0].remove(opCall.args["_id"], "");
      })
  ]


];

List<ServerOperation> commonOperations = [
  new ServerOperation('change',
    before: (ServerOperationCall opCall) {
      if (opCall.args.containsKey("_id")) throw new ValidationException("Cannot change _id of document");
    },
    operation: (ServerOperationCall opCall) {
      try {
        applyJSON(opCall.args, opCall.docs[0]);
      } catch (e, s){
        logger.warning("couldn not apply change properly", e, s);
      }
    })
];