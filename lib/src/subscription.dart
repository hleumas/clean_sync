// Copyright (c) 2013, the Clean project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of clean_sync.client;

final Logger logger = new Logger('clean_sync.subscription');

void handleData(List<Map> data, Subscription subscription, String author) {
  logger.fine('handleData: ${data}');
  var collection = subscription.collection;
  subscription.updateLock = true;
  collection.clear();
  collection.addAll(data);
  subscription.updateLock = false;
}

void _applyChangeList (List source, DataList target) {
  target.length = source.length;
  for (num i=0; i<target.length; i++) {
    if (!applyChange(source[i], target[i])) {
      target.set(i, source[i]);
    }
  }
}

void _applyChangeMap (Map source, DataMap target) {
  for (var key in new List.from(source.keys)) {
    if (target.containsKey(key)) {
      if(!applyChange(source[key], target[key])){
        target.add(key, source[key]);
      }
    } else {
      target.add(key, source[key]);
    }
  }
  for (var key in new List.from(target.keys)) {
    if (!source.containsKey(key)) {
      target.remove(key);
    }
  }
}

bool applyChange (source, target) {
  if (source is Map && target is Map) {
    _applyChangeMap(source, target);
    return true;
  }
  if (source is List && target is List) {
    _applyChangeList(source, target);
    return true;
  }
  if(source == target) {
    return true;
  }
  return false;
}

void destroyMap(Map m) {
  m.forEach((k,v){
    destroyStructure(v);
  });
  for (var k in new List.from(m.keys)) {
    m.remove(k);
  }
}

void destroyIterable(var l) {
  l.forEach((v){
    destroyStructure(v);
  });
  for (var v in new List.from(l)) {
    l.remove(v);
  }

}


void destroyStructure(s){
  if (s is Map) {
    destroyMap(s);
  } else
  if (s is Iterable) {
    destroyIterable(s);
  } else {}

}

num handleDiff(List<Map> diff, Subscription subscription, String author) {
  logger.fine('handleDiff: subscription: $subscription, author: $author,'
              'diffSize: ${diff.length}, diff: $diff');
  subscription.updateLock = true;
  DataSet collection = subscription.collection;
  var version = subscription._version;
  num res = -1;

  try {
    diff.forEach((Map change) {
      var _records = collection.findBy("_id", change["_id"]);
      DataMap record = _records.isNotEmpty? _records.first : null;
      String action = change["action"];

      logger.finer('handling change $change');
  //     it can happen, that we get too old changes
      if (!change.containsKey('version')){
        logger.warning('change does not contain "version" field. If not testing, '
                       'this is probably bug. (change: $change)');
        change['version'] = 0;
      } else if (version == null) {
        logger.warning('Subscription $subscription version is null. If not testing, '
                       'this is probably bug.');
      } else if(change['version'] <= version) {
        return;
      }
      if (action == "add") {
        res = max(res, change['version']);
        if (record == null) {
          logger.finer('aplying changes (add)');
          collection.add(change["data"]);
        } else {
          logger.finer('add discarded; same id already present');
          assert(author == change['author']);
        }
      }
      else if (action == "change" ) {
        // 1. the change may be for item that is currently not present in the collection;
        // 2. the field may be 'locked', because it was changed on user's machine, and
        // this change was not yet confirmed from server
         if (record != null) {
           if(!subscription._sentItems.containsKey(record['_id'])
             && !subscription._modifiedItems.changedItems.containsKey('_id')) {
              logger.finer('aplying changes (change)');
              res = max(res, change['version']);
              applyChange(change["data"], record);
           } else {
             logger.finer('discarding diff');
             throw "stop";
           }
        }
      }
      else if (action == "remove" ) {
        logger.finer('aplying changes (remove');
        res = max(res, change['version']);
        collection.remove(record);
      }
      logger.finest('applying finished: $subscription ${subscription.collection} ${subscription._version}');
    });
  } catch (e) {
    if (e is Exception) {
      throw e;
    }
  }
  logger.fine('handleDiff ends');
//  destroyStructure(diff);
  subscription.updateLock = false;
  return res;
}

class Subscription {
  // constructor arguments:
  String collectionName;
  DataSet collection;
  Connection _connection;
  // author field is not used anymore; we are keeping it in the DB mainly for debugging
  // and logging purposes
  String _author;
  IdGenerator _idGenerator;
  Function _handleData = handleData;
  Function _handleDiff = handleDiff;
  // Used for testing and debugging. If true, data (instead of diff) is
  // requested periodically.
  bool _forceDataRequesting = false;
  Map args = {};
  // Maps _id of a document to Future, that completes when server response
  // to document's update is completed
  Map<String, Future> _sentItems = {};
  // reflects changes to this.collection, that were not already sent to the server
  ChangeSet _modifiedItems = new ChangeSet();
  // flag used to prevent subscription to have multiple get_diff requests 'pending'.
  // This is mainly solved by clean_ajax itself; however, following is still possible:
  // 1. send_diff
  // 2. response obtained, response listener notified, end
  // 3. send_diff
  // 4. response listener process diff requested in step 1.
  // clearly, send_diff in step 3 can and should be avoided.
  bool requestLock = false;
  // this is another approach to obtain functionality formerly provided by clean_data
  // authors; when applying changes obtained from server, use this flag to
  // prevent detection and re-sending of these changes to the server
  bool updateLock = false;
  // all changes with version < _version MUST be already applied by this subscription.
  // Some of the later changes may also be applied; this happens, when collection
  // applies user change, but is not synced to the very last version at that moment.
  num _version = 0;

  // version exposed only for testing and debugging
  get version => _version;

  String toString() => 'Subscription(${_author}, ver: ${_version})';
  Completer _initialSync = new Completer();
  List<StreamSubscription> _subscriptions = [];
  StreamController _errorStreamController;
  Stream get errorStream {
    if (!_initialSync.isCompleted) throw new StateError("Initial sync not complete yet!");
    return _errorStreamController.stream;
  }

  /// Completes after first request to get data is answered and handled.
  Future get initialSync => _initialSync.future;

  Subscription.config(this.collectionName, this.collection, this._connection,
      this._author, this._idGenerator, this._handleData, this._handleDiff,
      this._forceDataRequesting, [this.args]);

  Subscription(this.collectionName, this._connection, this._author,
      this._idGenerator, [this.args]) {
    collection = new DataSet();
    collection.addIndex(['_id']);
    _errorStreamController = new StreamController.broadcast();
    start();
  }


  /**
   * Waits for initialSync of all provided subscriptions.
   */
  static Future wait(List<Subscription> subscriptions) {
    return Future.wait(
        subscriptions.map((subscription) => subscription.initialSync));
  }

  // TODO rename to something private-like
  void setupListeners() {
    _subscriptions.add(collection.onBeforeAdd.listen((data) {
      // if data["_id"] is null, it was added by this client and _id should be
      // assigned
      if(data["_id"] == null) {
        data["_id"] = _idGenerator.next();
      }
    }));

    var change = new ChangeSet();

    sendRequest(dynamic elem){
        Future result = _connection.send((){
          assert(_modifiedItems.changedItems.containsKey(elem));
          var req;
          if (_modifiedItems.addedItems.contains(elem)) {
            req = new ClientRequest("sync", {
              "action" : "add",
              "collection" : collectionName,
              "data" : elem,
              'args': args,
              "author" : _author
            });
          }
          if (_modifiedItems.strictlyChanged.containsKey(elem)) {
            req = new ClientRequest("sync", {
              "action" : "change",
              "collection" : collectionName,
              'args': args,
              "_id": elem["_id"],
              "change" : elem,
              "author" : _author
            });
          }
          if (_modifiedItems.removedItems.contains(elem)) {
            req = new ClientRequest("sync", {
              "action" : "remove",
              "collection" : collectionName,
              'args': args,
              "_id" : elem["_id"],
              "author" : _author
            });
          }
          _modifiedItems.changedItems.remove(elem);
          return req;
        }).then((result){
          if (result is Map)
            if (result['error'] != null)
              _errorStreamController.add(result['error']);
          return result;
        }).catchError((e){
          if(e is! CancelError) throw e;
        });

        var id = elem['_id'];
        _sentItems[id] = result;
        result.then((nextVersion){
          // if the request that already finished was last request modifying
          // current field, mark the field as free
          if (_sentItems[id] == result) {
            _sentItems.remove(id);
            // if there are some more changes, sent them
            if (_modifiedItems.changedItems.containsKey(elem)){
              sendRequest(elem);
            };
          }
        });
    };

    _subscriptions.add(collection.onChangeSync.listen((event) {
      if (!this.updateLock) {
        ChangeSet change = event['change'];
        _modifiedItems.mergeIn(change);
        for (var key in change.changedItems.keys) {
          if (!_sentItems.containsKey(key['_id'])) {
            sendRequest(key);
          }
        }
      }
    }));
  }

  _createDataRequest() => new ClientRequest("sync", {
    "action" : "get_data",
    "collection" : collectionName,
    'args': args
  });

  _createDiffRequest() {
    if (requestLock || _sentItems.isNotEmpty) {
      return null;
    } else {
      requestLock = true;
      return new ClientRequest("sync", {
      "action" : "get_diff",
      "collection" : collectionName,
      'args': args,
      "version" : _version
      });
    }
  }

  void setupDataRequesting() {
    // request initial data; this is also called when restarting subscription
    _connection.send(_createDataRequest).then((response) {
      if (response['error'] != null) {
        if (!_initialSync.isCompleted) _initialSync.completeError(new DatabaseAccessError(response['error']));
        else _errorStreamController.add(new DatabaseAccessError(response['error']));
        return;
      }
      _version = response['version'];
      _handleData(response['data'], this, _author);

      logger.info("Got initial data, synced to version ${_version}");

      // TODO remove the check? (restart/dispose should to sth about initialSynd)
      if (!_initialSync.isCompleted) _initialSync.complete();

      var subscription = _connection
        .sendPeriodically(_forceDataRequesting ?
            _createDataRequest : _createDiffRequest)
        .listen((response) {
          requestLock = false;
          // id data and version was sent, diff is set to null
          if (response['error'] != null) {
            throw new Exception(response['error']);
          }
          if(response['diff'] == null) {
            _version = response['version'];
            _handleData(response['data'], this, _author);
          } else {
            if(!response['diff'].isEmpty) {
              _version = max(_version, _handleDiff(response['diff'], this, _author));
            } else {
                if (response.containsKey('version'))
                   _version = response['version'];
            }
          }
        }, onError: (e){
          if (e is! CancelError)throw e;
        });
      _subscriptions.add(subscription);
    });
  }

  void start() {
    _errorStreamController.stream.listen((error){
      if(!error.toString().contains("__TEST__")) {
        logger.shout('errorStreamController error: ${error}');
      }
    });
    setupListeners();
    setupDataRequesting();
  }

  Future dispose() {
    return Future.forEach(_subscriptions, (sub) => sub.cancel());
  }

  Future close() {
    return dispose()
      .then((_) =>
        Future.wait(_sentItems.values))
      .then((_) =>
         new Future.delayed(new Duration(milliseconds: 100), (){
          collection.dispose();
    }));
  }

  Future restart([Map args]) {
    this.args = args;
    return dispose().then((_) {
      start();
    });
  }

  Stream onClose() {

  }
}

class DatabaseAccessError extends Error {
  final String message;
  DatabaseAccessError(this.message);
  String toString() => "Bad state: $message";
}
