import 'dart:io';

/// io 端网络异常判定
bool isNetworkException(Object error) =>
    error is SocketException || error is HttpException;
