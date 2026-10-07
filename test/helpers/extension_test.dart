import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/extension.dart';

void main() {
  group('StringExtension.capitalize', () {
    test('capitalizes lowercase word', () {
      expect('hello'.capitalize(), 'Hello');
    });

    test('lowercases rest of string', () {
      expect('HELLO'.capitalize(), 'Hello');
    });

    test('single char', () {
      expect('a'.capitalize(), 'A');
    });

    test('empty string returns empty', () {
      expect(''.capitalize(), '');
    });

    test('already capitalized', () {
      expect('Hello'.capitalize(), 'Hello');
    });

    test('mixed case', () {
      expect('hELLO wORLD'.capitalize(), 'Hello world');
    });

    test('numeric string unchanged', () {
      expect('123abc'.capitalize(), '123abc');
    });
  });
}
