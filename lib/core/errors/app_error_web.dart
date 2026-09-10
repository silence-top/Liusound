/// web 端网络异常判定：网络失败统一以 DioException 形态出现，
/// 由 adapter 层转成 AppError，这里无裸 socket 异常可判
bool isNetworkException(Object error) => false;
