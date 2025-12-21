---
title: "Spring GraphQLでエラーコードを返す"
emoji: "🚥"
type: "tech"
topics: ["java","graphql","springboot"]
published: true
published_at: 2025-12-22 00:12
---

:::message
本記事は [ZOZO Advent Calendar 2025](https://qiita.com/advent-calendar/2025/zozo) 22日目の記事です。
:::

## はじめに

GraphQLではエラーが発生しても`200`を返すのが慣例となっています。しかし、外形監視などではHTTPステータスコードでエラーを判定することが多く、すべてのレスポンスが`200`だとエラーの検知が難しくなります。

この記事では、[Spring GraphQL](https://spring.pleiades.io/projects/spring-graphql#overview)でエラー内容に応じて適切なHTTPステータスコードを返す方法を紹介します。

## なぜGraphQLは200を返すのか

[GraphQL over HTTP](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#status-codes)では、well-formedなリクエストに対して`200`を返すことが推奨されています。

主な理由は以下の通りです。

### 1. 部分的なレスポンスの存在

GraphQLでは、クエリの一部でエラーが発生しても、他の部分は正常にデータを返すことができます。レスポンスには`data`と`errors`の両方が含まれることがあり、従来のHTTPステータスコードでは「部分的な成功」を表現できません。

```json
{
  "data": {
    "user": {
      "name": "山田太郎"
    },
    "orders": null
  },
  "errors": [
    {
      "message": "注文情報の取得に失敗しました",
      "path": ["orders"]
    }
  ]
}
```

### 2. 中間層による改ざん防止

`4xx`や`5xx`ステータスコードは、プロキシやロードバランサーなどの中間層から生成される可能性があります。`200`を返すことで、レスポンスが確実にGraphQLサーバーから返されたものであることを保証できます。

## 標準実装でのレスポンス

まず、成功時のレスポンス例を示します。

```shell
curl -s -w '\n%{http_code}' http://localhost:8080/graphql \
    -H "Content-Type: application/json" \
    -d '{"query": "{ goods(id: \"1\") { id name type } }"}' \
    | { read -r body; read -r code; echo "$body" | jq .; echo "HTTP: $code"; }
{
  "data": {
    "goods": {
      "id": "1",
      "name": "ダウン",
      "type": "アウター"
    }
  }
}
HTTP: 200
```

次に、エラーが発生した場合のレスポンスを確認します。エラーが発生してもHTTPステータスコードは`200`のままです。

**構文エラー**
```shell
curl -s -w '\n%{http_code}' http://localhost:8080/graphql \
    -H "Content-Type: application/json" \
    -d '{"query": "{ goods(id: \"1\") { id name }"}' \
    | { read -r body; read -r code; echo "$body" | jq .; echo "HTTP: $code"; }

{
  "errors": [
    {
      "message": "Invalid syntax with offending token '<EOF>' at line 1 column 29",
      "locations": [
        {
          "line": 1,
          "column": 29
        }
      ],
      "extensions": {
        "classification": "InvalidSyntax"
      }
    }
  ]
}
HTTP: 200
```

**バリデーションエラー（存在しないフィールドをリクエスト）**
```shell
curl -s -w '\n%{http_code}' http://localhost:8080/graphql \
    -H "Content-Type: application/json" \
    -d '{"query": "{ goods(id: \"1\") { id name price } }"}' \
    | { read -r body; read -r code; echo "$body" | jq .; echo "HTTP: $code"; }

{
  "errors": [
    {
      "message": "Validation error (FieldUndefined@[goods/price]) : Field 'price' in type 'Goods' is undefined",
      "locations": [
        {
          "line": 1,
          "column": 28
        }
      ],
      "extensions": {
        "classification": "ValidationError"
      }
    }
  ]
}
HTTP: 200
```

## 外形監視での課題

しかし、この慣例は外形監視との相性が良くありません。外形監視ではHTTPステータスコードでエラーを判定することが一般的なため、GraphQLエンドポイントがすべて`200`を返すと、以下のような課題が発生します。

- 認証エラーやサーバーエラーが検知できない
- アラートの設定が複雑になる

## Spring GraphQLでHTTPステータスコードを返す

HTTPステータスコードを変更する方法を調査し、`GraphQlHttpHandler`の拡張が最も適していると判断しました。

| 方法                           | HTTPステータス変更 | 課題                                  |
|------------------------------|:-----------:|-------------------------------------|
| Servlet Filter               |     可能      | レスポンスボディを読む必要があり、パフォーマンスが低下する可能性がある |
| WebGraphQlInterceptor        |     不可      | レスポンスヘッダーは変更できるが、ステータスコードは変更できない    |
| DataFetcherExceptionResolver |     不可      | エラー内容のカスタマイズ用で、HTTPステータスコードは変更できない  |
| **GraphQlHttpHandler**       |   **可能**    | **エラー情報にアクセスでき、ステータスコードも設定可能**      |

`GraphQlHttpHandler`の`prepareResponse`メソッドは、GraphQLレスポンスをHTTPレスポンスに変換する最終段階です。このメソッドでは`WebGraphQlResponse`にアクセスでき、エラー情報を取得してHTTPステータスコードを設定できます。

以下が実装例です。作成したPRは[こちら](https://github.com/kohei-kohei/spring-graphql-app/pull/1)です。

```java
package com.example.app.controller.handler;

import graphql.ErrorClassification;
import java.util.Comparator;
import java.util.Map;
import org.springframework.graphql.execution.ErrorType;
import org.springframework.graphql.server.WebGraphQlHandler;
import org.springframework.graphql.server.WebGraphQlResponse;
import org.springframework.graphql.server.webmvc.GraphQlHttpHandler;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.function.ServerRequest;
import org.springframework.web.servlet.function.ServerResponse;
import reactor.core.publisher.Mono;

@Component
public class CustomGraphQlHttpHandler extends GraphQlHttpHandler {

  public CustomGraphQlHttpHandler(final WebGraphQlHandler handler) {
    super(handler);
  }

  @Override
  protected ServerResponse prepareResponse(
      final ServerRequest request, final Mono<WebGraphQlResponse> responseMono) {

    return ServerResponse.async(
        responseMono.map(
            response -> {
              final var httpStatus =
                  response.getErrors().stream()
                      .map(error -> toHttpStatus(error.getErrorType()))
                      // 複数のエラーが発生した場合は、最も優先度の高いステータスコードを返す
                      .max(Comparator.comparingInt(this::getErrorPriority))
                      .orElse(HttpStatus.OK);

              final Map<String, Object> body = response.toMap();
              final var contentType = MediaType.APPLICATION_JSON;
              final var writer = getWriteFunction(body, contentType);

              final var builder =
                  ServerResponse.status(httpStatus)
                      .headers(headers -> headers.addAll(response.getResponseHeaders()))
                      .contentType(contentType);

              return (writer != null) ? builder.build(writer) : builder.body(body);
            }));
  }

  private HttpStatus toHttpStatus(ErrorClassification errorClassification) {
    // Spring GraphQL の ErrorType
    if (errorClassification instanceof final ErrorType errorType) {
      return switch (errorType) {
        case BAD_REQUEST -> HttpStatus.BAD_REQUEST;
        case UNAUTHORIZED -> HttpStatus.UNAUTHORIZED;
        case FORBIDDEN -> HttpStatus.FORBIDDEN;
        case NOT_FOUND -> HttpStatus.NOT_FOUND;
        case INTERNAL_ERROR -> HttpStatus.INTERNAL_SERVER_ERROR;
      };
    }

    // graphql-java の ErrorType
    if (errorClassification instanceof final graphql.ErrorType graphqlErrorType) {
      return switch (graphqlErrorType) {
        case InvalidSyntax, ValidationError, NullValueInNonNullableField, OperationNotSupported ->
            HttpStatus.BAD_REQUEST;
        case DataFetchingException, ExecutionAborted -> HttpStatus.INTERNAL_SERVER_ERROR;
      };
    }

    return HttpStatus.INTERNAL_SERVER_ERROR;
  }

  private int getErrorPriority(HttpStatus status) {
    return switch (status) {
      case UNAUTHORIZED -> 5;
      case FORBIDDEN -> 4;
      case INTERNAL_SERVER_ERROR -> 3;
      case NOT_FOUND -> 2;
      case BAD_REQUEST -> 1;
      default -> 0;
    };
  }
}
```

### 実装のポイント

#### 1. エラータイプに応じたHTTPステータスコードのマッピング

`toHttpStatus`メソッドで、Spring GraphQLの`ErrorType`とgraphql-javaの`ErrorType`の両方に対応しています。

#### 2. 複数エラー時の優先度

GraphQLでは1つのリクエストで複数のエラーが発生することがあります。`getErrorPriority`メソッドで優先度を定義し、最も重要なエラーのステータスコードを返すようにしています。

### 動作確認

今回の例だとどちらのレスポンスも`400`が返るようになります。

**構文エラー**
```shell
curl -s -w '\n%{http_code}' http://localhost:8080/graphql \
    -H "Content-Type: application/json" \
    -d '{"query": "{ goods(id: \"1\") { id name }"}' \
    | { read -r body; read -r code; echo "$body" | jq .; echo "HTTP: $code"; }

{
  "errors": [
    {
      "message": "Invalid syntax with offending token '<EOF>' at line 1 column 29",
      "locations": [
        {
          "line": 1,
          "column": 29
        }
      ],
      "extensions": {
        "classification": "InvalidSyntax"
      }
    }
  ]
}
HTTP: 400
```

**バリデーションエラー**
```shell
curl -s -w '\n%{http_code}' http://localhost:8080/graphql \
    -H "Content-Type: application/json" \
    -d '{"query": "{ goods(id: \"1\") { id price } }"}' \
    | { read -r body; read -r code; echo "$body" | jq .; echo "HTTP: $code"; }
{
  "errors": [
    {
      "message": "Validation error (FieldUndefined@[goods/price]) : Field 'price' in type 'Goods' is undefined",
      "locations": [
        {
          "line": 1,
          "column": 23
        }
      ],
      "extensions": {
        "classification": "ValidationError"
      }
    }
  ]
}
HTTP: 400
```

## おわりに

この実装により、GraphQLエンドポイントでも外形監視でステータスコードによるエラー検知ができるようになります。ただし、GraphQLの慣例から外れることになるため、クライアント側でステータスコードを意識した実装が必要になる点には注意が必要です。

## 参考

- [GraphQL over HTTP Specification](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md)
- [Common HTTP Errors and How to Debug Them | GraphQL](https://graphql.org/learn/debug-errors/)
