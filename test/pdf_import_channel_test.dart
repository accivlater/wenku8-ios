import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.mewx.wenku8/pdf_import');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'convert sends the selected PDF and returns the manifest path',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <String, dynamic>{
          'manifestPath': '/tmp/Wenku8Imports/job/manifest.json',
        };
      });

      final result = await channel.invokeMapMethod<String, dynamic>('convert', {
        'path': '/tmp/selected.pdf',
        'name': '示例书.pdf',
      });

      expect(received?.method, 'convert');
      expect(received?.arguments, {
        'path': '/tmp/selected.pdf',
        'name': '示例书.pdf',
      });
      expect(result, {'manifestPath': '/tmp/Wenku8Imports/job/manifest.json'});
    },
  );

  test(
    'native conversion errors retain their code and Chinese message',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'ENCRYPTED_PDF',
          message: '不支持加密、受密码保护或禁止内容提取的 PDF，请选择未加密文件',
        );
      });

      await expectLater(
        channel.invokeMethod<void>('convert', {
          'path': '/tmp/locked.pdf',
          'name': '加密书.pdf',
        }),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'ENCRYPTED_PDF')
              .having((error) => error.message, 'message', contains('不支持加密')),
        ),
      );
    },
  );
}
