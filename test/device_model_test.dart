import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/src/device.dart';
import 'package:sightpane/src/device_model_io.dart';

void main() {
  group('androidModel', () {
    test(
      'reads maker, brand, model and the marketing name when there is one',
      () {
        const props = {
          'ro.product.manufacturer': 'Xiaomi',
          'ro.product.brand': 'Xiaomi',
          'ro.product.model': '24072PX77G',
          'ro.product.marketname': 'Xiaomi 14T Pro',
        };
        expect(androidModel((name) => props[name] ?? ''), {
          'manufacturer': 'Xiaomi',
          'brand': 'Xiaomi',
          'model': '24072PX77G',
          'model_name': 'Xiaomi 14T Pro',
        });
      },
    );

    test('leaves out what the device does not set', () {
      const props = {
        'ro.product.manufacturer': 'samsung',
        'ro.product.brand': 'samsung',
        'ro.product.model': 'SM-S918B',
      };
      expect(androidModel((name) => props[name] ?? ''), {
        'manufacturer': 'samsung',
        'brand': 'samsung',
        'model': 'SM-S918B',
      });
    });
  });

  group('iosModel', () {
    test('sends the identifier; the backend names it', () {
      expect(iosModel('iPhone17,3', null), {
        'manufacturer': 'Apple',
        'brand': 'Apple',
        'model': 'iPhone17,3',
      });
    });

    test('in the simulator, reports the simulated device, not the Mac', () {
      expect(iosModel('arm64', 'iPhone17,1')['model'], 'iPhone17,1');
    });
  });

  test('a desktop test host sends no phone model', () {
    final dev = SightpaneDevice.collect();
    expect(dev.containsKey('model'), isFalse);
    expect(dev.containsKey('manufacturer'), isFalse);
  });
}
