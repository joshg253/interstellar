import 'package:flutter_test/flutter_test.dart';
import 'package:interstellar/src/utils/utils.dart';

void main() {
  test('a name that already has a host keeps it', () {
    expect(
      communityGlobalName('test@other.example', null, 'a.example'),
      '!test@other.example',
    );
  });

  test('a bare name takes the host from its ActivityPub id', () {
    expect(
      communityGlobalName(
        'test',
        'https://home.example/c/test',
        'viewer.example',
      ),
      '!test@home.example',
    );
  });

  test('a bare name with no id falls back to the viewing server', () {
    expect(
      communityGlobalName('test', null, 'viewer.example'),
      '!test@viewer.example',
    );
  });
}
