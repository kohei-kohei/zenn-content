---
title: "Slackに流しているアラートをいい感じに集計するActionsを作成しました！"
emoji: "🐈"
type: "tech"
topics: ["githubactions", "slack"]
published: true
---

## はじめに

稼働中のアプリケーションのアラートをSlackに通知し、その通知のたびに何かしらの対策を講じるチームは多いと思います。しかし、これらのアラートを集計し、動向や傾向を把握したのちに、改善に役立てているチームはそれほど多くはないのではないでしょうか。

その改善を支援するために、アラートを**ざっくりと**集計するGitHub Actionsを作成しました。

https://github.com/marketplace/actions/aggregate-alerts

2024年8月時点では以下のサービスからのアラートを集計できます。

- Datadog
- Sentry
- PagerDuty
- AWS Chatbot
- digdag-alert

## 事前準備

Slack Appを作成し、適切な権限を設定する必要があります。

1. Slack Appを作成し、パブリックチャンネルの場合は`channels:history`、プライベートチャンネルの場合は`groups:history`の権限を付与します。
2. 集計結果をSlackに送信したい場合は、`chat:write`の権限も追加してください。
2. 作成したSlack Appをアラートが流れているチャンネルに招待します。
3. Slack Appの`Bot User OAuth Token`をリポジトリのSecretsに追加します。

> 詳しい手順は[公式のQuickstart](https://api.slack.com/quickstart)を参考にしてください。

## 使い方

Slack Appの招待とSecretsの登録が済んだら、あとは上記のActionsを呼び出すだけです。
以下のコードは、PRの作成・更新・再オープン時にトリガーされますが、スケジュールや手動でのトリガーの方が適していると思います。

```
on:
  pull_request:
    branches:
      - main

jobs:
  aggregate-alerts:
    name: Aggregate alerts
    runs-on: ubuntu-latest
    steps:
      - uses: kohei-kohei/alert-aggregator@v0
        env:
          SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
        with:
          get-channel-id: 'CXXXXXXXXXX'
          since: '2024-08-01T00:00:00+09:00'
          until: '2024-08-08T00:00:00+09:00'
```

`env.SLACK_BOT_TOKEN`には先ほどSecretsに登録したトークンを指定し、`get-channel-id`にはアラートを集計したいチャンネルIDを指定してください。チャンネルIDの確認方法は[こちらの記事](https://intercom.help/yoom/ja/articles/5480072-slack%E3%81%AE%E3%83%81%E3%83%A3%E3%83%B3%E3%83%8D%E3%83%ABid%E3%81%AE%E7%A2%BA%E8%AA%8D%E6%96%B9%E6%B3%95)が参考になると思います。

`since`と`until`を指定しない場合は、実行日の前日から1週間前までのアラートを集計します。タイムゾーンは実行時のサーバーに依存しているため、日本時間に設定したい場合は[こちらの例](https://github.com/marketplace/actions/aggregate-alerts#just-aggregating-alerts)のように`env.TZ: 'Asia/Tokyo'`を指定してください。

以下のアラートを集計した結果はこんな感じで表示されます。

![](/images/alert-aggregator/alert.png)

![](/images/alert-aggregator/actions.png)

`send-channel-id`に送信先のチャンネルIDを指定すれば、集計結果をSlackに送信することもできます。

![](/images/alert-aggregator/result.png)

## 今後の展望

まだ、いくつかの改善点があるため`v0`として公開していますが、テストを充実させ、チャンネル名を表示できるようになったら`v1`に更新する予定です。

需要があれば送信用のSlack Appを別で指定できるようにしたり、集計結果を`outputs`として出力できるようにしたり、日本語で表示できるようにしていきたいです。

## おわりに

このActionsが、皆さんの改善活動に少しでも貢献できれば幸いです！
