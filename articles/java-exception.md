---
title: "VavrでJavaの例外処理をスマートに！"
emoji: "☕️"
type: "tech"
topics: ["java"]
published: true
---

:::message
本記事は**ZOZO Advent Calendar 2024**の17日目の記事です。
:::

@[card](https://qiita.com/advent-calendar/2024/zozo)

## はじめに

この記事では、私たちのチームがどのように例外処理に向き合い、その改善を進めてきたかを紹介します。

プロジェクト初期はチームにJavaの経験者が少なかったため、できるだけ独自の**検査例外**を作成し、これを利用して例外処理を強制していました。これにより、エラー処理の抜け漏れを防ぐことができたと思います。

しかし、プロジェクトが進むにつれ、以下の理由からコードが煩雑になっていきました。

1. Java標準の関数型インターフェースを実装するラムダ式やメソッド参照では、検査例外を直接投げることができない
2. 例外処理のコード量や`throws`宣言が増える

この問題を解決するためにJava用の関数型ライブラリである[Vavr](https://vavr.io/)を採用しました。このライブラリを用いることで、例外処理を簡潔かつ柔軟に記述できるようになりました。

## 例外処理の改善方法

最近では、エラーや異常系を伝播させるために以下のアプローチを採用しています。
- Java標準の[Optional](https://docs.oracle.com/javase/jp/17/docs/api/java.base/java/util/Optional.html)を使用し、エラーではなく「値の非存在」を明示的に表現する
- `Vavr`で提供されている[Try](https://docs.vavr.io/#_try)や[Either](https://docs.vavr.io/#_either)を使用して、関数型プログラミングのスタイルで例外処理を行う

`Either`の使い方は[Javaで鉄道指向プログラミング(Railway Oriented Programming)を実践する](https://qiita.com/cocet33000/items/2ac0e84d803120035c5b)に詳しく書かれているのでそちらを参考にしてください。

この記事では`Try`を使った例外処理を紹介します。

### 今までの例外処理の課題

例として、`ItemId`という仮のクラスを用いて説明します。このクラスは`Long`型の値を持ち、`null`または0以下の場合に検査例外を投げます。

```java
public class ItemId {
  private final Long value;

  public ItemId(final Long value) throws InvalidItemIdException {
    if (value == null || value <= 0) {
      // 独自の検査例外を投げる
      throw new InvalidItemIdException("ItemId must be positive and non-null");
    }
    this.value = value;
  }
}
```

この設計では、ラムダ式内で`ItemId`のインスタンスを生成する場合、以下のように`try-catch`を使用する必要があります。このコードでは最終的に**非検査例外**を投げているので、当初の目的である**明示的な例外処理**ができていない上にコードが煩雑になっています。検査例外を投げたい場合はさらに`try-catch`を書く必要があるため、コードがさらに複雑になります。

```java
    final var idList = List.of(1L, 2L, 3L);

    final var itemIdList = idList.stream()
      .map(value -> {
        try {
          return new ItemId(value);
        } catch (final InvalidItemIdException e) {
          throw new RuntimeException(e);
        }
      })
      .toList();
```

### Vavrの`Try`を使った例外処理

そこで`Try`を使用することでこの課題を解決しました。`Try`は例外が発生した場合は`Failure`を返し、正常に処理が終了した場合は`Success`を返します。この仕組みにより、例外が発生しうることをコードで明確に表現しつつ、例外処理を簡潔に記述できます。また、例外処理を記述する場所やタイミングを呼び出し側に委ねられるため、コードの柔軟性が向上します。

```java
public class ItemId {
  private final Long value;

  private ItemId(final Long value) {
    this.value = value;
  }

  public static Try<ItemId> of(final Long value) {
    return Try.of(
        () -> {
          if (value == null || value <= 0) {
            throw new InvalidItemIdException("Item id must be positive and non-null");
          }
          return new ItemId(value);
        });
  }
}
```

この設計によって、`try-catch`を直接記述する必要がなくなり、コードの煩雑さを軽減できます。さらに、例外が発生した場合でも、それを`Failure`として簡潔に伝播させることができ、エラー処理も容易に行えます。

```java
    final var idList = List.of(1L, 2L, 3L);

    final var tryItemIdList = idList.stream().map(ItemId::of).toList();

    final var firstFailure = tryItemIdList.stream().filter(Try::isFailure).findFirst();
    if (firstFailure.isPresent()) {
      throw (InvalidItemIdException) firstFailure.get().getCause();
    }

    final var itemIdList = tryItemIdList.stream().filter(Try::isSuccess).map(Try::get).toList();
```

## まとめ

Vavrを活用することで、従来の方法より簡潔かつ柔軟に例外処理を行うことができました。ただし、検査例外による強制力が失われるため、コードレビュー時の確認が重要になります。チームの成熟度やプロジェクトの要件に応じて最適な例外処理を選びましょう。

Vavrを使って素敵なJavaライフを！
