---
title: "Debeziumでメッセージフィルタリングを行う"
emoji: "🐏"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["debezium", "kafka"]
published: true
---

:::message
本記事は [ZOZO Advent Calendar 2023](https://qiita.com/advent-calendar/2023/zozo) 12日目の記事です。
:::

## はじめに

Debeziumでは`filter single message transform(SMT)`を使用することでApache Kafkaに送信するメッセージをフィルタリングすることができます。この記事では[公式ドキュメント](https://debezium.io/documentation/reference/2.4/transformations/filtering.html)を参考に、スクリプトエンジンである`JSR223`をプラグインとして`filter SMT`を動かしてみます。

## 準備

Apache KafkaのDockerイメージはConfluent社が提供しているものを使用し、Debezium周りは「[DebeziumでCDCを構築してみた](https://zenn.dev/stafes_blog/articles/ikkitang-691e9913644952)」の記事を参考にさせていただきました。

2023年12月上旬時点のStableバージョンで動作検証します。
```
Apache Kafka: 3.5
Debezium: 2.4
```

設定を追加する前の`docker-compose.yaml`は以下の通りです。
https://github.com/kohei-kohei/debezium-playground/blob/2268ec6fe3dc507bb066607895e0da40479a049a/docker-compose.yaml

## 設定

Debezium connector for MySQLで`filter SMT`を動かすための手順です。

1. セキュリティの観点からDebezium connectorには`filter SMT`が含まれていないので、[公式ドキュメント](https://debezium.io/documentation/reference/2.4/transformations/filtering.html#set-up-filter)の`1. Download the scripting SMT archive`から`debezium-scripting-2.4.1.Final.tar.gz`を取得します。

2. Debeziumで式言語を使用するために[Groovy](https://groovy.apache.org/download.html)のStableバージョンのbinaryをダウンロードします。今回は`4.0.16`を使用しました。

3. 取得した圧縮ファイルを解凍し、以下のjarファイルをDebeziumのプラグインを管理しているディレクトリに配置します。Dockerでは`/kafka/connect/debezium-connector-mysql/`に配置しました。
```
debezium-scripting-2.4.1.Final.jar
groovy-4.0.16.jar
groovy-json-4.0.16.jar
groovy-jsr223-4.0.16.jar
```

4. Debeziumの設定に以下を追加します。今回は[イベント値](https://access.redhat.com/documentation/ja-jp/red_hat_integration/2020-q2/html-single/debezium_user_guide/index#_change_event_value)を元にメッセージをフィルタリングします。この設定では行が削除されたときに発生する[tombstoneイベント](https://access.redhat.com/documentation/ja-jp/red_hat_integration/2022.q1/html/debezium_user_guide/about-values-in-debezium-mysql-change-events#:~:text=%E3%82%88%E3%81%86%E3%81%AB%E3%81%97%E3%81%BE%E3%81%99%E3%80%82-,%E5%BB%83%E6%A3%84%20(tombstone)%20%E3%82%A4%E3%83%99%E3%83%B3%E3%83%88,-%E8%A1%8C%E3%81%8C%E5%89%8A%E9%99%A4)もオフにしているため、データの作成と更新のイベントのみをKafkaに送信します。
```
"transforms": "filter",
"transforms.filter.type": "io.debezium.transforms.Filter",
"transforms.filter.language": "jsr223.groovy",
"transforms.filter.condition": "value.op == 'c' || value.op == 'u'",
"tombstones.on.delete": "false"
```



:::message alert
`include.schema.changes`を`false`にしていないとスキーマ変更のメッセージで以下のエラーが発生してしまいます。
`javax.script.ScriptException: org.apache.kafka.connect.errors.DataException: op is not a valid field name`
ref: https://stackoverflow.com/questions/70244854/failing-to-generate-a-filter-on-debezium-connector-with-error-op-is-not-a-vali
:::

変更の内容は以下のPRを参照してください。
https://github.com/kohei-kohei/debezium-playground/pull/3

## 動作検証

以下のコマンドを実行し、データの作成・更新・削除を行ったときにKafkaに送信されるメッセージを確認します。
```
docker exec mysql mysql -u root -ppassword playground -e "INSERT INTO items (name) VALUE ('Tシャツ');"
docker exec mysql mysql -u root -ppassword playground -e "UPDATE items SET name = 'ロングスリーブTシャツ' WHERE id = 1;"
docker exec mysql mysql -u root -ppassword playground -e "DELETE FROM items WHERE id = 1;"
```

メッセージフィルタリングを導入する前は作成・更新・削除のイベントがすべてKafkaに送信されています。最後の`null`はtombstoneイベントによるものです。

```
docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:9092 \
       --topic debezium_playground_topic.playground.items --from-beginning

{"before":null,"after":{"id":1,"name":"Tシャツ","registered_at":1702278557988,"updated_at":1702278557988},"source":{"version":"2.4.1.Final","connector":"mysql","name":"debezium_playground_topic","ts_ms":1702278557000,"snapshot":"false","db":"playground","sequence":null,"table":"items","server_id":1,"gtid":null,"file":"mysql-bin.000003","pos":398,"row":0,"thread":12,"query":null},"op":"c","ts_ms":1702278558014,"transaction":null}
{"before":{"id":1,"name":"Tシャツ","registered_at":1702278557988,"updated_at":1702278557988},"after":{"id":1,"name":"ロングスリーブTシャツ","registered_at":1702278557988,"updated_at":1702278563519},"source":{"version":"2.4.1.Final","connector":"mysql","name":"debezium_playground_topic","ts_ms":1702278563000,"snapshot":"false","db":"playground","sequence":null,"table":"items","server_id":1,"gtid":null,"file":"mysql-bin.000003","pos":748,"row":0,"thread":13,"query":null},"op":"u","ts_ms":1702278563530,"transaction":null}
{"before":{"id":1,"name":"ロングスリーブTシャツ","registered_at":1702278557988,"updated_at":1702278563519},"after":null,"source":{"version":"2.4.1.Final","connector":"mysql","name":"debezium_playground_topic","ts_ms":1702278569000,"snapshot":"false","db":"playground","sequence":null,"table":"items","server_id":1,"gtid":null,"file":"mysql-bin.000003","pos":1133,"row":0,"thread":14,"query":null},"op":"d","ts_ms":1702278569055,"transaction":null}
null
```

メッセージフィルタリングを導入した後は作成・更新のイベントのみがKafkaに送信されています。
```
docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:9092 \
       --topic debezium_playground_topic.playground.items --from-beginning

{"before":null,"after":{"id":1,"name":"Tシャツ","registered_at":1702278727374,"updated_at":1702278727374},"source":{"version":"2.4.1.Final","connector":"mysql","name":"debezium_playground_topic","ts_ms":1702278727000,"snapshot":"false","db":"playground","sequence":null,"table":"items","server_id":1,"gtid":null,"file":"mysql-bin.000003","pos":398,"row":0,"thread":12,"query":null},"op":"c","ts_ms":1702278727394,"transaction":null}
{"before":{"id":1,"name":"Tシャツ","registered_at":1702278727374,"updated_at":1702278727374},"after":{"id":1,"name":"ロングスリーブTシャツ","registered_at":1702278727374,"updated_at":1702278736121},"source":{"version":"2.4.1.Final","connector":"mysql","name":"debezium_playground_topic","ts_ms":1702278736000,"snapshot":"false","db":"playground","sequence":null,"table":"items","server_id":1,"gtid":null,"file":"mysql-bin.000003","pos":748,"row":0,"thread":13,"query":null},"op":"u","ts_ms":1702278736132,"transaction":null}
```

## おわりに

`filter SMT`を使用することでメッセージのフィルタリングを行うことができました。データをローテートするときにメッセージを送らないようにするなど、活用方法はあると思うのでぜひ利用してみてください。
