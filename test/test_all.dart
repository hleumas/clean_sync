// Copyright (c) 2013, the Clean project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


import 'publisher_test.dart' as publisher_test;
import 'mongo_provider_test.dart' as mongo_provider_test;
import 'subscription_test.dart' as subscription_test;
import 'id_generator_test.dart' as id_generator_test;
import 'exception_test.dart' as exception_test;
import 'collection_modification_test.dart' as collection_modification_test;
import 'subs_random_test.dart' as subs_random_test;
import 'mongo_provider_random_test.dart' as mp_random_test;

import 'package:unittest/unittest.dart';
import 'package:unittest/vm_config.dart';
import 'package:logging/logging.dart';

final Logger logger = new Logger('clean_sync');

main() {
  run(new VMConfiguration());
}

run(configuration) {
  unittestConfiguration = configuration;
  hierarchicalLoggingEnabled = true;
  logger.level = Level.WARNING;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.loggerName} ${rec.level.name}: ${rec.message} ${rec.error} ${rec.stackTrace}');
  });
  Logger.root.level = Level.WARNING;

  mongo_provider_test.main();
  publisher_test.run();
  subscription_test.run();
  id_generator_test.main();
  exception_test.run();
  collection_modification_test.run();
  subs_random_test.run(100);
  mp_random_test.run(30);
}
