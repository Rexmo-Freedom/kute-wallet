// Captured from BDK Dart rc.3 before removal. PUBLIC TEST SEEDS, never fund.
// SQLite databases contain no transactions or user data. Used only in tests.
const String nativeBdkFixtureJson = r'''
{
  "source": "bdk_dart v1.0.0-rc.3, public test mnemonic, no real funds",
  "entropy": [
    {
      "hex": "00000000000000000000000000000000",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    },
    {
      "hex": "ffffffffffffffffffffffffffffffff",
      "mnemonic": "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"
    },
    {
      "hex": "9f86d081884c7d659a2feaa0c55ad015",
      "mnemonic": "panel custom call awesome sick ready hamster wool patch client reduce clay"
    }
  ],
  "wallets": [
    {
      "network": "bitcoin",
      "scriptType": "bip44",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "pkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/44'/0'/0'/0/*)#7um67zvr",
      "internal": "pkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/44'/0'/0'/1/*)#0g7mrhum",
      "accountXpub": "xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj",
      "database": "bitcoin_bip44.sqlite",
      "addresses": {
        "0": "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA",
        "5": "19a7HGg32ecPQo49rDeM2NSFJHPqrwSJto",
        "20": "1FSCcgcjLvp8fE8qfTRLNFzPWaLZKSVnbM"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dy04bVxjA8ZkYbAwYk6qV1aJUg1gUIlJsfF+0qjEDpSGkMSaEVpE1l+N4ascGj7kki0p2N32Bvkmlpu0qiy66aB+h75Bdlx1f4kswTqtukPX/aayM5xx7vvOdMweOxyj7D3atmlDylepTraaEpXlJlqXPFEWSJJfzuCn1+JzHRN9zWXo7l/Tx2fe+2T1p3nMi+VP+l3M/+Bpzn87+7b2Y/X1Gm31/+sOZ21M/zhY8J1OPJQAAxlXd8nsC6bTcOKppeknoZjFnCtuoWse1StXZrVpnwszZx0V7RNF8OqOmsqqSTW3sqsqIisqy0ldimUpWfZRV9u47j4Pd3VXFqZOzyqa4UHb2suq2mhksUzZ272/0Hfoys3MvlTlS7qpHyvLAG/e91YqyouxnMzvp7MG8O2ClZal12D4pOb9p5LTTWqX1PDci7FxoROHNesrnCaiq3JgclsKSZtdyVXEmtJIwR5XNjUriQM3hWexPRi9Fgy98M6vd1NSXPJ7AwoLcuNVtQ+3C7vwzdSky56ATRO1i9Lmr2rlTs9VpnUBsIcrdIDrHxJll1HqxrSp5q/pG1ddRNrwznsDSkvxdb7BqZaNQqdp9u7OXou0UDETczUBG3VIz6l5a3e+1rFltZVXRSxWjmCsI60mhNmRAdoo1u/DmMDYqZacRzm+wVqWcq1lPRffVm+pW6mA3q9wJXTWMm+cePHX/mXqDOTrrDuwsjRrMnWa3B2/nia8e9XoCi4tyI9rX0ZXTmt3bmx7S3c3jQ/O3qpw5ZUOyc6aVTsWwy7g1bkdeye0UNN+319zwtDuwvTique0g261t78/MvpQ+cAZ1fafbVrff3Zr2DufcgaL6L6eCgWvo0lwwUOr3/y1NNU9wZ8odSC2MjrcbrO2te9ytbqn3Rnar0+3enudSt7SPO90ydKAOvyavGrS9mSA50fqBUH/WjeRcK5VELdd8pdN+J7PHTjPaI+aKoslLsV5R8b+Nqb4mDR0kB5Nvm+CvCKPdEVcUuusrrvY1c+uNlPT2Jq5osNM+yxzZJUr6czV9V1l2qn2iBJ1Zpze0WllxZpOCVn4icpeOl0XtvFIttnP3OgXfyq0Zsp7uhmobBfFUs/t2b1wKtlOwrJQ1Z7IaMaWfiartTGpX/yCJ3njbtNQ5VzvlnSfNtf1Ud1Hv/0nyv/L/5f/D2QEAAAAAANfFu17Xmre5ni+KZ0ZBs8qtD+D8HteS3P6E60lVOy64brpcK1PNA6WKoZVaFX03XIve3ucl0631/wvJ/8JZ///pf0VqAQAAAAC4Pt5zrcmX1v9e/+D63/OOa0UeXP675lyLcm/5f6N5/1+e+01yNgAAAAAArrdGQvJIjXgjvnBcLCx/HQ8bUVMLamuRyEdrweb2+OL4VI9tVOx8umzln18YW+fV/ecPrJPT9c2Nh1m7UEw/0oyzPftw++iLhw8LBe08FTcjmejh/uH21p5uJVLnsa8yRkivXtx7dnjv+XZ4c99REcXiqVk4MJPPdvXYyUU4mU2W75nfrAXXbq8sJc4jzxN5YV6XoELNoIoxuxo7zUd0q2ZUrHJz/S/NM4QAAAAAABhn06z/AQAAAAAYe63v//t/kZwNAAAAAABcO5vShFT3BbtCSTMWSySNYCKqiVAsmgiHRDIcyefjsbAmIjFtXYsZofi6Hs6H9FhQSxhiPZbn+/8AAAAAAIw/vv8PAAAAAMD44/4/AAAAAADjj/v/AAAAAACMP+7/AwAAAAAw/rj/DwAAAADA+Gv//38/S84GAAAAAACuG1WeqPvkWMIwo+FgQoQNPSREVF+PhcW6YYpgPhmNG7purhuReDQs9Hw8EUno62YyZAS1iJ6IBhPxkJicbq3/f5WcDQAAAAAAXD+bE3Wf9/9+AMDf/wMAAAAAMP74+38AAAAAAMbfP5hXI28AEAEA"
    },
    {
      "network": "bitcoin",
      "scriptType": "bip44",
      "xpub": "xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj",
      "external": "pkh([00000000/44'/0'/0']xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj/0/*)#6ns025wz",
      "internal": "pkh([00000000/44'/0'/0']xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj/1/*)#t84whp76",
      "accountXpub": "xpub6BosfCnifzxcFwrSzQiqu2DBVTshkCXacvNsWGYJVVhhawA7d4R5WSWGFNbi8Aw6ZRc1brxMyWMzG3DSSSSoekkudhUd9yLb6qx39T9nMdj",
      "database": "bitcoin_bip44_watch.sqlite",
      "addresses": {
        "0": "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA",
        "5": "19a7HGg32ecPQo49rDeM2NSFJHPqrwSJto",
        "20": "1FSCcgcjLvp8fE8qfTRLNFzPWaLZKSVnbM"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dy04bVxjA8ZkYbAwYk6qV1aJUg1gUIlJ8vyxa1ZiB0gBpjAmhVWTNjMfx1I4NHmMMi0p2N32Bvkmlpu0qiy66aB+h75Bdlx1f4gs2TqtukPX/aayM5xx7vvOdMweOxyiHj/eMii5lS+UXSkUKCIuCKAqfSZIgCDbrcVfocVmPqb7novB2NuHj6veu+QNh0XEmuOPuVws/uBoLn87/7azN/z6nzL8/++Hc/Zkf53OOs5lnAgAAk6puuB2eREJsnFQUtaCrmXw6o5ta2TitlMrWbtmo6pm0eZo3xxQtJpJyPCVLqfjmniyNqSitSn0lRkZKyU9T0sEj63G0t7cuWXXSRjGj16Tdg5S8IycHy6TNvUebfYe+TO7ux5Mn0kP5RFodeOO+t1qT1qTDVHI3kTpatHuMhCi0DptnBes3jbRyXim1nqfHhJ32jSm8W4+7HB5ZFhvTo1JYUMxKuqxXdaWgZ8aVLYxL4kDN0VnsT0YvRYMvvJ7VbmrqKw6HZ2lJbNzrtqFSMzv/zAxFZh20gqjUxp+7rFxYNVud1gnE1PViN4jOMb1qaJVebOtS1ihfq/omyoZzzuFZWRG/6w1WpajlSmWzb3d+KNpOwUDE3Qwk5W05KR8k5MNey5rV1tYltVDS8umcbjzPVUYMyE6xYuauD2OtVLQaYf0Ga5SK6YrxQu++ekvejh/tpaQHvpuGcfPcg6fuP1NvMIfm7Z7dlXGDudPs9uDtPHHVQ06HZ3lZbIT6Orp0XjF7e7Mjurt5fGT+1qWqVTYiO1WlcK6Puoxb43bsldxOQfN9e80NzNo9O8vjmtsOst3a9v7c/CvhA2tQ13e7bbW77a1p73jB7snL/3IqGLiGhuaCgVK3+29hpnmCBzN2T3xpfLzdYE1n3WFvdUu9N7JbnW729hxD3dI+bnXLyIE6+pq8adD2ZoLYVOsHQv2yG8mFUijolXTzlVb7rcyeWs1oj5gbiqaHYr2h4n8bU31NGjlIjqbfNsHfEEa7I24otNfXbO1r5t61lPT2pm5osNU+IzO2S6TE53LiobRqVftE8lqzTm9otbJizSY5pfhcTw8dL+qVi1I5387dmxR8K7ZmyHqiG6qp5fQXitm3e2co2E7BqlRUrMlqzJRe1cumNand/IMkdOdt01LnXO2Ud5401/Yz3UW9+yfB/dr9l/sPawcAAAAAANwW7zptG87mej6vX2o5xSi2PoBzO2wrYvsTrudl5TRnu2uzrc00DxRKmlJoVXTdsS07e5+XzLbW/y8F90tr/f+n+zWpBQAAAADg9njPtiEOrf+d7sH1v+Md25o4uPy3LdiWxd7y/07z/r+48JtgbQAAAAAA3G6NqOAQGpFGZOk0n1v92tuxEQx+tOFtbs9qp+dqeLNkZhNFI3tV07YvyodXj42zc//W5pOUmcsnnipa9cA83jn54smTXE65iEcywWTo+PB4Z/tANaLxi/BXSc2nlmv7l8f7VzuBrUNLSc/nzzO5o0zsck8Nn9UCsVSsuJ/5ZsO7cX9tJVw0vf7QxdVtCcrXDKoSDV7kTiNh1ahoJaPYXP8LiwwhAAAAAAAm2SzrfwAAAAAAJl7r+//uXwRrAwAAAAAAt86WMCXUXd4uXywTDkdjmjcaUnRfOBQN+PRYIJjNRsIBRQ+GFb8S1nwRvxrI+tSwV4lquj+c5fv/AAAAAABMPr7/DwAAAADA5OP+PwAAAAAAk4/7/wAAAAAATD7u/wMAAAAAMPm4/w8AAAAAwORr//9/PwvWBgAAAAAAbhtZnKq7xHBUy4QC3qge0FSfrodUfzig+7WM7s3GQhFNVTN+LRgJBXQ1G4kGo6o/E/NpXiWoRkPeaMSnT8+21v+/CtYGAAAAAABun62pusv5fz8A4O//AQAAAACYfPz9PwAAAAAAk+8f332ppgAQAQA=",
      "masterFingerprint": "00000000"
    },
    {
      "network": "bitcoin",
      "scriptType": "bip49",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "sh(wpkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/49'/0'/0'/0/*))#47nwva0a",
      "internal": "sh(wpkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/49'/0'/0'/1/*))#namthsyf",
      "accountXpub": "xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7",
      "database": "bitcoin_bip49.sqlite",
      "addresses": {
        "0": "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf",
        "5": "3QrMAP4ZG3a7Y1qFF5A4sY8MeSUxZ8Yxjy",
        "20": "3Qyobv1ZUg79doGWePdBWygEt5n5B97SXt"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dTW8aRxgH8F1j82KD16laodZKtZYPNZFT87a8HFoV43XimDgOxomdKkKzu4PZgAGza3ByqAS99Av0m1Rq2pxy7KH9CP0OueXYYSEsmJe06sVC/58WZdkZ2GeemR17WKwcPc7oJhUL1fo5McUIt8LxPPedKHIc52CPW5zNxx7zA8957uMc3NeNn3zeA27FdcEJKeHt8s++9vK33veeK+8fS8T7+eKXS3fcv3iLrgv3cw4AAGBWtXTB5U+n+fapSZQyVbRSXqOGWtdrZrXOdut6g2p5o1YyphStpLNyKieLudR2RhanVBQ3xIESXRNz8klOPHjEHseZzKbI6uT1ikavxL2DnHxPzg6XiduZR9sDhw6zew9T2VNxXz4VN4beeOCtAmJAPMpl99K54xWnX0/znHXYuCiz3zTy5NKsWs/zU8LOh6YU3mqlfC6/LPPthXEpLBPDzNdpg5Iy1aaVLU9L4lDN8VkcTIadouEXXs9qPzWtdZfLv7rKt2/322BeGb1/3CORsYMsCPNq+rnrpMlqWp3WC8SgtNIPoneMNnTVtGPbFAt6/VrVD1G2PUsu//o6/6M9WElFLVbrxsCudyTaXsFQxP0MZOVdOSsfpOUju2WdaoFNUSlX1VK+SPWzojlmQPaKiVG8PozVaoU1gv0Gq1creVM/p/1X78i7qeNMTrwbmjSMO+cePvXgmezBLHmd/r31aYO51+zu4O098bUkj8u/tsa3pYGOrl6ahr23OKa7O8fH5m9TbLCyMdlpkPIlHXcZW+N26pXcTUHnfe3mRhad/ntr05rbDbLb2u7+kvct9wUb1K29fludgtOa9p4uO/0l+V9OBUPX0MhcMFQqCO85d+cEd91Of2p1erz9YA1Py+W0uqVlj2yr0w17zzXSLd3jrFvGDtTx1+SkQWvPBMl56wdC62U/kiYpl6mZ77yStZ9ltsaa0R0xE4oWRmKdUPG/jamBJo0dJMcLH5vgJ4TR7YgJhc5WwNG9Zm5fS4m9Nz+hwax9uja1S8T0fTm9L26wat+IQTbr2EPLygqbTYqkckbzI8cr1GxW66Vu7j6k4AfemiFb6X6ohlqk58QY2J0bCbZXsCFWCJuspkzpDVo32KQ2+QeJNPexaal3rm7Ke086a3t3f1Ev/MoJ74S/hT/ZDgAAAAAAAADcFJ96HFueznq+RF+qRaJXrA/gBJdjne9+wnVWJ7Wi45bDEXB3DpSrKilbFX1zjjWP/XnJorX+f80Jr9n6/y/hHVILAAAAAAAAcHN85tjiR9b/HmF4/e/6xBHgh5f/jmXHGm8v/+c69//55Tcc2wAAAAAAAABuovY25+LaqXZq1ShuNGul4sb38YgqaSRItqLJr7aCne35Ve1SiaVjlcfN++SpclR/ZUjms9BF/FzKJtXD/SQ9rR083KWGfmKc1s/U0GFCaWQyKWomHxTuvzg92X+Rq+4k1O2s0XxwcqIou7WTs6ZhNJ8cpp692n9IQi+Oa+HSk9K9J8fkAYlvBbfuBALrZ41CTTPMVzcpspAVGdESxWgwThTdVKt6pbP+51YwmAAAAAAAAABm2SLW/wAAAAAAAAAzz/r+v/A7xzYAAAAAAAAAuHF2uHmu5Qv2hZJaLJZIqsGERGgoJiUiIZqMRAuFeCxCaDRGwiSmhuJhJVIIKbEgSag0HCvg+/8AAAAAAAAAsw/f/wcAAAAAAACYfbj/DwAAAAAAADD7cP8fAAAAAAAAYPbh/j8AAAAAAADA7MP9fwAAAAAAAIDZ1/3//37j2AYAAAAAAAAAN43Mz7d8vETVGJEkTQvFImpBJVKQRLWkJCUS0TBRI0qQhsJhhUixgiZF4uFIIh4NhSNqgiY0RZWotLBorf/fcGwDAAAAAAAAgJtnZ77l8/zfDwDw9/8AAAAAAAAAsw9//w8AAAAAAAAw+/4BcPRD9gAQAQA="
    },
    {
      "network": "bitcoin",
      "scriptType": "bip49",
      "xpub": "xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7",
      "external": "sh(wpkh([00000000/49'/0'/0']xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7/0/*))#5n4hyzxa",
      "internal": "sh(wpkh([00000000/49'/0'/0']xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7/1/*))#pjmpuanz",
      "accountXpub": "xpub6C6nQwHaWbSrzs5tZ1q7m5R9cPK9eYpNMFesiXsYrgc1P8bvLLAet9JfHjYXKjToD8cBRswJXXbbFpXgwsswVPAZzKMa1jUp2kVkGVUaJa7",
      "database": "bitcoin_bip49_watch.sqlite",
      "addresses": {
        "0": "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf",
        "5": "3QrMAP4ZG3a7Y1qFF5A4sY8MeSUxZ8Yxjy",
        "20": "3Qyobv1ZUg79doGWePdBWygEt5n5B97SXt"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dy24aVxjA8ZnggHGMcapWqI1SjeVF7SipuXgwLFoVk0ni2HEcjBM7VYQOw2AmYCDM+JIsKkE3fYG+SaWmzSrLLtpH6Dtkl2WHS7jYmLTqxkL/nwZlmHNgvvOdM8c+DFa2H22YtqHkK7UDYSsRaVaSZek7RZEkyeU8rko9Pucx0fdclj7OJX199JNvelOa9byQ/An/25mffY2Zb6ffe0+m/7gipj+f+vLKjclfpgueF5PPJAAAxlXd9HsCyaTc2LNFtmRkc8VMzrD0mlm1KzVnt2YeGbmMVS1aI4pmkyktkdaUdGJ1Q1NGVFQWlL4SM6ektd20svnQeexsbNxUnDoZs5wzTpS1zbR2V0sNlimrGw9X+w5tpdYeJFJ7yrq2pywMvHHfWy0qi8p2OrWWTO/MugNmUpZah60XJec3jYw4tCut55kRYWdCIwqv1hM+T0DT5MblYSksCcvO1IwjQ5SM3KiymVFJHKg5PIv9yeilaPCFp7PaTU193uMJXLsmN65322CfWJ1/Js9E5hx0grBPRp+7Jo6dmq1O6wRiGUa5G0TnmHFk6nYvtptK3qydqvohyob3iicwPy//2BusoqwXKjWrb3f6TLSdgoGIuxlIaXe0lLaZ1LZ7LWtWW7ypZEsVvZgpGOZ+wR4yIDvFwiqcHsZ6pew0wvkN1qyUM7Z5YHRffVu7k9jZSCu3QucN4+a5B0/df6beYFan3YG1+VGDudPs9uDtPPHVVa8nMDcnN9S+jq4c2lZvb2pIdzePD83fTeXIKRuSnSNROjSGXcatcTvySm6noPm+veZGptyBu3OjmtsOst3a9v6V6bfSF86grq912+r2u1vT3pMZd6Co/cupYOAaOjMXDJT6/e+lyeYJbk26A4lro+PtBmt56x53q1vqvZHd6nSrt+c50y3t4063DB2ow6/J8wZtbyaIT7R+INRfdiM5FqWSYWear3Ta72S26jSjPWLOKbp8JtZzKv63MdXXpKGDZOfyxyb4c8Jod8Q5he76oqt9zVw/lZLe3sQ5DXbaZ+ZGdomSvKcl15UFp9o3StCZdXpDq5UVZzYpiPK+kTlzvGzYx5VasZ27Dyn4QW7NkPVkN1RLLxgHwurbvXQm2E7BglIWzmQ1Yko/MmqWM6md/4NEvfSxaalzrnbKO0+aa/vJ7qLe/6vkf+f/2/+nswMAAAAAAC6KT72uJW9zPV80XuoFYZZbH8D5Pa55uf0J135NVAuuqy7X4mTzQKmii1Krou+Sa87b+7xkqrX+fy35Xzvr/7/870gtAAAAAAAXx2euJfnM+t/rH1z/ez5xLcqDy3/XjGtO7i3/LzXv/8szbyRnAwAAAADgImqsSh6pkWgkrlmFheNqsbDwfbBjaTn+1VKwuT07qR5mo8lo+dHxPfEku117Zan209CLlQM1Fde31uPGXnXzwR3DMnetvdq+HtqKZY82NhKGHb+fv/d8b3f9ebpyO6avpqzj+7u72eyd6u7+sWUdP95KPH21/kCEnu9Uw8XHxbuPd8R9sbIUXLqxuDivlpcLL1+diIsUWagVWfX5QfVQlF9lTVuvmOXm+l+aZTABAAAAADDOplj/AwAAAAAw9lrf//f/LjkbAAAAAAC4cG5LE1LdF+wKxXPRaCyuB2OqMEJRNRYJGfHIcj6/Eo0IYzkqwiKqh1bC2Ug+lI0GRUw3wtE83/8HAAAAAGD88f1/AAAAAADGH/f/AQAAAAAYf9z/BwAAAABg/HH/HwAAAACA8cf9fwAAAAAAxl/7///7TXI2AAAAAABw0WjyRN0nq4YeFaqay4WiET2vCzUolnNxVY3FlsNCj2SDRigczgo1ms+pkZVwJLayHApH9JgRy2V11VAvT7XW/28kZwMAAAAAABfP7Ym6z/t/PwDg7/8BAAAAABh//P0/AAAAAADj7x/9pSMMABABAA==",
      "masterFingerprint": "00000000"
    },
    {
      "network": "bitcoin",
      "scriptType": "bip84",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "wpkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/84'/0'/0'/0/*)#3gqy5rdn",
      "internal": "wpkh(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/84'/0'/0'/1/*)#qu99fkat",
      "accountXpub": "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V",
      "database": "bitcoin_bip84.sqlite",
      "addresses": {
        "0": "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
        "5": "bc1qnpzzqjzet8gd5gl8l6gzhuc4s9xv0djt0rlu7a",
        "20": "bc1qy62dyq937vfjr5e8tj3ltx7zc6fw958tmvqa5l"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dXU8iVxjA8RlREBVxmzakNduM8aK6cSs4gtCkTRHHXSu6Lou6brMhwzAssyAoM6L2ogn0pl+g36RJt+3Vple9aD9Cv8Pe9bLDy/KiyLbpjSH/X4bsMOfAPOc5Z44eBrNPHscNS5eypfKxakmyMCOIovClJAmC4LAfd4QOj/0Y7XouCu/mED6tfO+Z2hVmXKeCN+p9Pf2Dpzb9xdTf7oup3yfVqQ8nPp68N/7jVM51Ov5cAABgWFUNr8sXi4m1I0tNF/R0Jp/K6KZWNk6sUtneLRsVPZMyT/LmgKKZWEKJJhUpGV2PK9KAitKC1FViZKSk8jQp7T6yH/vx+JJk10kZxYx+IW3tJpUHSqK3TFqPP1rvOrSX2NqJJo6kbeVIWuh54663WpQWpSfJxFYsuT/j9BkxUWgcNk8L9m8aKfXMKjWepwaEnQoMKLxTjXpcPkURa2P9UlhQTStV1iu6WtAzg8qmByWxp2b/LHYno5Oi3hdezWo7NdV5l8s3OyvW7rbbYF2YrX/Gr0VmH7SDsC4Gn7usnts1G53WCsTU9WI7iNYxvWJoVie2JSlrlK9UfRtlzT3p8s3Pi991Bqta1HKlstm1O3Ut2lZBT8TtDCSUTSWh7MaUJ52W1astLknpQknLp3K68SJn9RmQrWLVzF0dxlqpaDfC/g3WKBVTlnGst1+9oWxG9+NJ6X7gpmFcP3fvqbvP1BnMwSmnb2t+0GBuNbs5eFtPPNWg2+WbmxNrwa6OLp1ZZmdvok9314/3zd+SVLHL+mSnohbO9H6XcWPcDrySmymov2+nufKE0/dgblBzm0E2W9vcn5x6LXxkD+rqVrutTq+zMe0dTjt9eeVfTgU919C1uaCn1Ov9Wxivn+D+uNMXnR0cbztY0111ORvdUu2M7Eanm50917VuaR63u6XvQO1/Td40aDszQWS08QOhetmO5FwtFHQrVX+l3X47syd2M5oj5oaisWux3lDxv42prib1HST7Y++a4G8Io9kRNxQ6q4uO5jVz90pKOnujNzTYbp+RGdglUuyhEtuWFuxqn0t+e9bpDK1GVuzZJKcWX+ipa8eLunVeKuebuXubgm/FxgxZjbVDNbWcfqyaXbsj14JtFSxIRdWerAZM6RW9bNqT2s0/SIIj75qWWudqprz1pL62H28v6r0/Cd433r+8f9g7AAAAAADgtnjf7Vh219fzef1Sy6lGsfEBnNflmBebn3C9KKsnOccdh2NxvH6gUNLUQqOiZ8Qx5+58XjLRWP+/Eryv7PX/n943pBYAAAAAgNvjA8eyeG397/b2rv9d7zkWxd7lv2PaMSd2lv8j9fv/4vRvgr0BAAAAAHCb1T4TXEItUovMnp/kcwtfr8laMKP61eXw6ifL/vr2/OLkLB2KqdZhxnhmlDLH+3py4yQcTwZL5XDxOL29q51dVr5ZO7zMmweb+e311cTD89iG/PTyrLKnpCun0cdHcjm6Z+YOtZ14aW8lu7O5s/1w76vVZ/qzp0cH+7l4JXCwU365F1vbOwwdLPuX7y3On2tyUa6oxVsTVaAeVaESfFnRM1basLSSUayv/4UZBhEAAAAAAMNsgvU/AAAAAABDr/H9f+8vgr0BAAAAAIBbZ0MYFaoef1sgkgmFwhHNHw6qeiAUDMsBPSKvZrNrIVnVV0PqihrSAmsraTkbSIf8aljTV0JZvv8PAAAAAMDw4/v/AAAAAAAMP+7/AwAAAAAw/Lj/DwAAAADA8OP+PwAAAAAAw4/7/wAAAAAADL/m///3s2BvAAAAAADgtlHE0apHDKv+tbVVVUv717L+QCatB9PySjgTCGYz2bCuqukVORsKR1Q5Es6m5dVQ0J8NyJFQYEUOhFazIX1sorH+/1WwNwAAAAAAcPtsjFY97v/7AQB//w8AAAAAwPDj7/8BAAAAABh+/wDaVbJ8ABABAA=="
    },
    {
      "network": "bitcoin",
      "scriptType": "bip84",
      "xpub": "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V",
      "external": "wpkh([00000000/84'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V/0/*)#psezw22r",
      "internal": "wpkh([00000000/84'/0'/0']xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V/1/*)#syurnl6m",
      "accountXpub": "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V",
      "database": "bitcoin_bip84_watch.sqlite",
      "addresses": {
        "0": "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
        "5": "bc1qnpzzqjzet8gd5gl8l6gzhuc4s9xv0djt0rlu7a",
        "20": "bc1qy62dyq937vfjr5e8tj3ltx7zc6fw958tmvqa5l"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dXU8iVxjA8RlREAVxmzakNduM8aK6cSvvQpM2RRx3rei6LOq6zYYMMCxTEJBB1L1oAr3pF+g3adJte7XpVS/aj9DvsHe97PCyvMjLtumNIf9fhuww58A85zlnjh4Gs08eR7WKKmWK5TOlInmFRUEUhS8lSRAEk/G4I3TZjcd0z3NReDeT8Gn1e7vtQFi0nAuOsOP1wg/2+sIXtr+tV7bf5xXbh3Mfz9+b/dGWtZzPPhcAAJhUNc1hcUYiYv20oiTzajKdS6RVPVXWSpVi2dgta1U1ndBLOX1M0WIkJofjshQPb0VlaUxFaVXqKdHSUlx+GpcOHhmPo2h0XTLqJLRCWr2Sdg/i8gM51l8mbUUfbfUcOozt7odjp9KefCqt9r1xz1utSWvSk3hsNxI/WjQ7tYgoNA/r53njN42EclEpNp8nxoSdcI8pvFML2y1OWRbrM8NSmFf0SqKsVlUlr6bHlS2MS2JfzeFZ7E1GN0X9L7yZ1U5qaisWi3NpSazf7bShcqW3/5kdiMw4aARRuRp/7rJyadRsdlo7EF1VC50g2sfUqpaqdGNblzJa+UbVt1HWrfMW58qK+F13sCqFVLZY1nt2bQPRtgv6Iu5kICbvyDH5ICI/6basUW1tXUrmi6lcIqtqL7KVIQOyXazo2ZvDOFUsGI0wfoPVioVERTtTO6/elnfCR9G4dN89ahg3zt1/6t4zdQez32Z27q6MG8ztZrcGb/uJvea3WpzLy2Ld39PRxYuK3t2bG9LdjeND87cuVY2yIdmpKvkLddhl3By3Y6/kVgoa79ttrnfO7HywPK65rSBbrW3tz9teCx8Zg7q222mr2WFuTnsnC2ZnTv6XU0HfNTQwF/SVOhx/C7ONE9yfNTvDS+Pj7QSrW2sWc7Nbat2R3ex0vbtnGeiW1nGjW4YO1OHX5KhB250JQtPNHwi1604kl0o+r1YSjVca7TcyWzKa0RoxI4pmBmIdUfG/jameJg0dJEcz75rgR4TR6ogRhebamql1zdy9kZLu3vSIBhvt09Jju0SKPJQje9KqUe1zyWXMOt2h1cyKMZtklcILNTFwvKBWLovlXCt3b1PwrdicIWuRTqh6KqueKXrP7tRAsO2CVamgGJPVmCm9qpZ1Y1Ib/YPEP/Wuaal9rlbK208aa/vZzqLe8ZPgeOP4y/GHsQMAAAAAAG6L962mDWtjPZ9Tr1NZRSs0P4BzWEwrYusTrhdlpZQ13TGZ1mYbB/LFlJJvVrRPmZat3c9L5prr/1eC45Wx/v/T8YbUAgAAAABwe3xg2hAH1v9WR//63/KeaU3sX/6bFkzLYnf5P9W4/y8u/CYYGwAAAAAAt1n9M8Ei1EP10NJlKZdd/drVthH0fbLhamzPr0oXyUBEqZyktWdaMX12pMa3S8Fo3F8sBwtnyb2D1MV19eXmyXVOP97J7W35Yg8vI9vep9cX1UM5WT0PPz71lsOHevYktR8tHnoy+zv7ew8Pv/I9U589PT0+ykar7uP98jeHkc3Dk8Dxhmvj3tpKSVdfXno85VsTlbsRlX59US7kA2dJrZIqaoXG+l9YZBABAAAAADDJ5lj/AwAAAAAw8Zrf/3f8IhgbAAAAAAC4dbaFaaFmd3W4Q+lAIBhKuYJ+RXUH/EGvWw15fZnMZsCrqL6A4lECKfemJ+nNuJMBlxJMqZ5Ahu//AwAAAAAw+fj+PwAAAAAAk4/7/wAAAAAATD7u/wMAAAAAMPm4/w8AAAAAwOTj/j8AAAAAAJOv9f///SwYGwAAAAAAuG1kcbpmF4OKa3PTp6SSrs2My51Oqv6k1xNMu/2ZdCaoKkrS480EgiHFGwpmkl5fwO/KuL2hgNvjdQd8mYA6M9dc//8qGBsAAAAAALh9tqdrduv//QCAv/8HAAAAAGDy8ff/AAAAAABMvn8AWhZAiQAQAQA=",
      "masterFingerprint": "00000000"
    },
    {
      "network": "bitcoin",
      "scriptType": "bip86",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "tr(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/86'/0'/0'/0/*)#zeg4ksen",
      "internal": "tr(xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu/86'/0'/0'/1/*)#ndd5t9ft",
      "accountXpub": "xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ",
      "database": "bitcoin_bip86.sqlite",
      "addresses": {
        "0": "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr",
        "5": "bc1pl4frjws098l3nslfjlnry6jxt46w694kuexvs5ar0cmkvxyahfkq0m445f",
        "20": "bc1p2hjxr5mp0u5av0807d2hah7vlzq3npllfsff0cgve79gwc0k5z9sew2hul"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dTU8bRxjA8d0YbAwYk6qV1aJUizgUIlL8jn1oVTAbQmNIMJAUVZE1Xq+xwbFhd3Egh0p2L/0C/SaVmrannKoe2o/Q75Bbjl2/xC/YOK16Qdb/p7Wy3hl7n3lmdmC8RtnbTRYsXcmVjefCUkLSrCTL0leKIkmSw37cljo89mOs67ksvZ9D+rzyg2d6R5p1nUneNe/rmR89tZkvp9+6L6b/mBLTH09+OnV34qfpvOts4pkEAMCoqha8Ll8iIdcOLZEp6pnsSTqrm5pROLXKhr1rFCp6Nm2enphDimYTKXVtX1X219aTqjKkorKodJUUssq++s2+svPIfhwkk8uKXSddKGX1C2VrZ1/dVFO9Zcp68tF616HHqa3ttdSh8lA9VBZ73rjrrZaUJWVvP7WV2D+YdfoKCVlqHDbPivZvGmlxbpUbz9NDwk4HhhTerq55XD5VlWvjg1JYFKaVNvSKLop6dljZzLAk9tQcnMXuZHRS1PvCq1ltp6a64HL55ubk2p12G6wLs/XPRF9k9kE7COti+LkN8cKu2ei0ViCmrpfaQbSO6ZWCZnViW1ZyBeNK1XdR1txTLt/Cgvx9Z7CKkpYvG2bX7nRftK2CnojbGUip99WUupNQ9zotq1dbWlYyxbJ2ks7rhaO8NWBAtoqFmb86jLVyyW6E/RtsoVxKW4XnevvVG+r9tYPkvnIvcN0wrp+799TdZ+oM5si007e1MGwwt5rdHLytJ55qxO3yzc/LtUhXR5fPLbOzNzmgu+vHB+ZvWanYZQOyUxHFc33QZdwYt0Ov5GYK6u/baW5o0unbnB/W3GaQzdY296emX0uf2IO6utVuq9PrbEx7T2ecvhP1X04FPddQ31zQU+r1vpUm6ie4N+H0rc0Nj7cdrOmuupyNbql2Rnaj083OnquvW5rH7W4ZOFAHX5PXDdrOTBAfa/xAqF62I3khikXdStdfabffzuyp3YzmiLmmaLwv1msq/rcx1dWkgYPkYPx9E/w1YTQ74ppCZ3XJ0bxm7lxJSWdv7JoG2+0rZId2iZJ4oCYeKot2tS8Uvz3rdIZWIyv2bJIXpSM93Xe8pFsvysZJM3fvUvCd3Jghq4l2qKaW158Ls2v3Vl+wrYJFpSTsyWrIlF7RDdOe1K7/QRK59b5pqXWuZspbT+pr+4n2ot77s+R94/3b+6e9AwAAAAAAbooP3Y4Vd309f6JfanlRKDU+gPO6HAty8xOuI0Oc5h23HY6lifqBYlkTxUZFzy3HvLvzeclkY/3/SvK+stf/f3nfkFoAAAAAAG6Ojxwrct/63+3tXf+7PnAsyb3Lf8eMY17uLP9v1e//yzO/S/YGAAAAAMBNV4tKLqkWqUXmLGPx29WQFskKv1iJRT9b8de3Zxen55no+tH6kambp08raup+KPlg9zyaKJ1lKzm1Ym1ru8eHhpZ6eREJ7X59vHchjOOgyB0+1ZKWXt58cnK5uhE6eLjxOL57aSRPjd3Qk4SaKB+G45e57Ib6YDNhbW8fx4OnKf3A3F3xr9xdWjCOguHVfDR+Q2IK1GM6PvdHjJdBkSlYWrlQqq//pVkGEAAAAAAAo2yS9T8AAAAAACOv8f1/76+SvQEAAAAAgBtnQxqTqh5/WyCejUZjcc0fiwg9EI3EQgE9HgrncqvRkNDDUREUUS2wGsyEcoFM1C9imh6M5vj+PwAAAAAAo4/v/wMAAAAAMPq4/w8AAAAAwOjj/j8AAAAAAKOP+/8AAAAAAIw+7v8DAAAAADD6mv//3y+SvQEAAAAAgJtGlceqHjkbCYZFTPfnosF4TIhcKJsRfj0UjUXiIhIRwVBwNRuOh/RQLu7PhOP+WDCQjQZFWMvahQERHp9srP9/k+wNAAAAAADcPBtjVY/7/34AwN//AwAAAAAw+vj7fwAAAAAARt8/0IOmRAAQAQA="
    },
    {
      "network": "bitcoin",
      "scriptType": "bip86",
      "xpub": "xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ",
      "external": "tr([00000000/86'/0'/0']xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ/0/*)#rzavtsv9",
      "internal": "tr([00000000/86'/0'/0']xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ/1/*)#jkcdk9ua",
      "accountXpub": "xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ",
      "database": "bitcoin_bip86_watch.sqlite",
      "addresses": {
        "0": "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr",
        "5": "bc1pl4frjws098l3nslfjlnry6jxt46w694kuexvs5ar0cmkvxyahfkq0m445f",
        "20": "bc1p2hjxr5mp0u5av0807d2hah7vlzq3npllfsff0cgve79gwc0k5z9sew2hul"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dTU8bRxjA8d0YbAw2JlUrq0WpFnEoRKT4BRv70KpgNoTGkGAgKaoia7xeY2PHht3FgRwq2b30C/SbVGrannKqemg/Qr9Dbjl2/RK/gHFa9YKs/09rZb0z9j7zzOzAeI2yt5ssWLqSqxjPhaWEpRlJlqWvFEWSJIf9uC11ee3HWM9zWXo/h/R59QevZ0eacZ1KvjXf6+kfvfXpLz1v3eeeP6aE5+PJT6fuTvzkybtOJ55JAACMqlrB5/InEnL90BKZkp7JFtNZ3dSMwolVMexdo1DVs2nzpGgOKZpJpNS1fVXZX1tPqsqQisqC0lNSyCr76jf7ys4j+3GQTC4pdp10oZzVz5WtnX11U031lynryUfrPYcep7a211KHykP1UFnoe+Oet1pUFpW9/dRWYv9gxukvJGSpedg8Ldm/aaTFmVVpPk8PCTsdHFJ4u7bmdflVVa6PD0phSZhW2tCruijp2WFl08OS2FdzcBZ7k9FNUf8LL2e1k5ravMvln52V63c6bbDOzfY/E1cisw/aQVjnw89tiBd2zWantQMxdb3cCaJ9TK8WNKsb25KSKxiXqr6Lsu6ecvnn5+Xvu4NVlLV8xTB7dj1Xom0X9EXcyUBKva+m1J2EutdtWaPa4pKSKVW0YjqvF47y1oAB2S4WZv7yMNYqZbsR9m+whUo5bRWe651Xb6j31w6S+8q94HXDuHHu/lP3nqk7mCMep39rfthgbje7NXjbT7y1iNvln5uT65Gejq6cWWZ3b3JAdzeOD8zfklK1ywZkpypKZ/qgy7g5bodeya0UNN6329zwpNO/OTesua0gW61t7U95Xkuf2IO6ttVpq9PnbE57T6ed/qL6L6eCvmvoylzQV+rzvZUmGie4N+H0r80Oj7cTrOmuuZzNbql1R3az083unutKt7SO290ycKAOviavG7TdmSA+1vyBULvoRPJClEq6lW680m6/ndkTuxmtEXNN0fiVWK+p+N/GVE+TBg6Sg/H3TfDXhNHqiGsKnbVFR+uauXMpJd29sWsabLevkB3aJUrigZp4qCzY1b5QAvas0x1azazYs0lelI/09JXjZd16UTGKrdy9S8F3cnOGrCU6oZpaXn8uzJ7dW1eCbRcsKGVhT1ZDpvSqbpj2pHb9D5LIrfdNS+1ztVLeftJY2090FvW+nyXfG9/fvj/tHQAAAAAAcFN86HYsuxvr+aJ+oeVFodz8AM7ncszLrU+4jgxxknfcdjgWJxoHShVNlJoVvbccc+7u5yWTzfX/K8n3yl7//+V7Q2oBAAAAALg5PnIsy1fW/25f//rf9YFjUe5f/jumHXNyd/l/q3H/X57+XbI3AAAAAABuunpUckn1SD0yaxkL3wbalmPRz5YDje3Z+clZJrp+tH5k6ubJ06qauh9OPtg9iybKp9lqTq1a29ru8aGhpV6eR8K7Xx/vnQvjOCRyh0+1pKVXNp8UL1Y3wgcPNx7Hdy+M5ImxG36SUBOVw5X4RS67oT7YTFjb28fx0ElKPzB3lwPLdxfnjZeiapnV+A2JKdiI6bioZYvxM5EpWFqlUG6s/6UZBhAAAAAAAKNskvU/AAAAAAAjr/n9f9+vkr0BAAAAAIAbZ0Mak2reQEcwno1GY3EtEIsIPRiNxMJBPR5eyeVWo2Ghr0RFSES14GooE84FM9GAiGl6KJrj+/8AAAAAAIw+vv8PAAAAAMDo4/4/AAAAAACjj/v/AAAAAACMPu7/AwAAAAAw+rj/DwAAAADA6Gv9/3+/SPYGAAAAAABuGlUeq3nlbCS0ImJ6IBcNxWNC5MLZjAjo4WgsEheRiAiFQ6vZlXhYD+figcxKPBALBbPRkFjRsnZhUKyMTzbX/79J9gYAAAAAAG6ejbGa1/1/PwDg7/8BAAAAABh9/P0/AAAAAACj7x+Q8kHgABABAA==",
      "masterFingerprint": "00000000"
    },
    {
      "network": "testnet",
      "scriptType": "bip44",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "pkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/44'/1'/0'/0/*)#g8ser03l",
      "internal": "pkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/44'/1'/0'/1/*)#en4c76p8",
      "accountXpub": "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
      "database": "testnet_bip44.sqlite",
      "addresses": {
        "0": "mkpZhYtJu2r87Js3pDiWJDmPte2NRZ8bJV",
        "5": "mvWgTTtQqZohUPnykucneWNXzM5PLj83an",
        "20": "n4FMbkd9mUiAHDj8mdfmd1rf6fmEq9f38a"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dT08iZxzA8ZlFQRTEbdqQ1mwzxsPqxq0gIM6hTRFH16y6W8Tu2mZDhmGQKQjIjKg9NIFe+gb6Tpp025720EMP7Uvoe9jbHjv8Wf4osG16MeT7CcRhngfm9/yeZx58GIyHX+wZli5lS5VT1ZJCwpwgisLnkiQIgsO+3xW6vPZ9ouexKLybQ/ik+oPXcyDMuc4EX8z3avZHb332M88b96XnjxnV8+H0xzMPpn7y5FxnUy8EAADGVc3wufzxuFg/ttR0QU9n8qmMbmoVo2yVKvZmxajqmZRZzpsjiubiCSWWVKRkbHNPkUZUlJaknhIjIyWV50np4Il9P9rbW5HsOimjmNEvpd2DpLKjJPrLpM29J5s9u54mdvdjiWPpsXIsLfW9cM9LLUvL0mEysRtPHs05/UZcFJq7zbOC/ZtGSj23Ss3HqRFhp4IjCu/WYl6XX1HE+uSgFBZU00pV9KquFvTMqLLZUUnsqzk4i73J6Kao/4nXs9pJTW3R5fLPz4v1e502WJdm+8fUjcjsnXYQ1uXoY1fUC7tms9PagZi6XuwE0d6nVw3N6sa2ImWNyrWqb6Osu2dc/sVF8fvuYFWLWq5UMXs2PTeibRf0RdzJQELZVhLKQVw57LasUW15RUoXSlo+ldONk5w1YEC2i1Uzd30Ya6Wi3Qj7N1ijVExZxqneefaWsh072ktKD4PDhnHj2P2H7j1SdzBHPE7/7uKowdxudmvwth94axG3y7+wINYjPR1dOrfM7tb0gO5u7B+YvxWpapcNyE5VLZzrg07j5rgdeSa3UtB43W5zQ9NO/87CqOa2gmy1trU943klfGQP6tpup61On7M57T2bdfrzyr+cCvrOoRtzQV+pz/dGmGoc4OGU0x+bHx1vJ1jTXXM5m91S647sZqeb3S3XjW5p7be7ZeBAHXxODhu03ZlAnmi+IdSuOpFcqIWCbqUaz7Tbb2e2bDejNWKGFE3eiHVIxf82pnqaNHCQHE2+a4IfEkarI4YUOmvLjtY5c+9aSrpbE0MabLfPyIzsEin+SIk/lpbsap9KAXvW6Q6tZlbs2SSnFk/01I39Rd26KFXyrdy9TcF3YnOGrMU7oZpaTj9VzZ7NOzeCbRcsSUXVnqxGTOlVvWLak9rwN5LInXdNS+1jtVLeftBY2091FvW+nwXfa9/fvj/tDQAAAAAAcFu873asuhvr+bx+peVUo9j8AM7nciyKrU+4TipqOee463AsTzV2FEqaWmhW9N5xLLi7n5dMN9f/LwXfS3v9/5fvNakFAAAAAOD2+MCxKt5Y/7t9/et/13uOZbF/+e+YdSyI3eX/ncb1f3H2d8G+AQAAAABwu9U3BJdQj9aj8+V8bunraEiLZNSAuhoO318N3l8N3H9hlc/TW/HI9mFx0/hqa/80Z5zHT5/Fjs29i5O940olKVdiZ9Xk1WH2PB6vnJjPvt24uNx/fnQoJ9Oy8eV+VUukq9ta7NFOfn8r8vhyI1/KhXfOzg92DpLZUi6bj5ZPvsmpT+OZ5+VSWl0NrD5YXjTPwqcX2lXmtgQVbARVjpjrxUwkbOmmVdStxvpfmGMIAQAAAAAwzqZZ/wMAAAAAMPaa3//3/SrYNwAAAAAAcOtsCRNCzRt4Sw6FdDUQVDMBXZc3wmsBORqV06qqayFNz8iBrBrKhgMb0aAcWVvPbmSi0WxYDof4/j8AAAAAAOOP7/8DAAAAADD+uP4PAAAAAMD44/o/AAAAAADjj+v/AAAAAACMP67/AwAAAAAw/lr//+8Xwb4BAAAAAIDbRhEnal5RVtWsvKatycFgMK1GAhk9GwoHM+taOqzKETkQTWuqroe1YFizS9fDkbVANBDRQ/K6nNaj62uT0831/2+CfQMAAAAAALfP1kTN6/6/HwDw9/8AAAAAAIw//v4fAAAAAIDx9w+0xKg0ABABAA=="
    },
    {
      "network": "testnet",
      "scriptType": "bip44",
      "xpub": "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
      "external": "pkh([00000000/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/0/*)#daskr9nz",
      "internal": "pkh([00000000/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/1/*)#uf4h7sr6",
      "accountXpub": "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
      "database": "testnet_bip44_watch.sqlite",
      "addresses": {
        "0": "mkpZhYtJu2r87Js3pDiWJDmPte2NRZ8bJV",
        "5": "mvWgTTtQqZohUPnykucneWNXzM5PLj83an",
        "20": "n4FMbkd9mUiAHDj8mdfmd1rf6fmEq9f38a"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dT08iZxzA8RlREAVxmzakNduM8bC6cSsIiHNoU8TRNavuVrG7ttmQYRhkCoLOjOjuoQn00jfQd9Kk2/a0hx56aF9C38PeeuzwZ/kjyLbpxZDvJxCHeR6Y3/N7nnn0YSAefrFr2LqUK5unqi1FhFlBFIXPJUkQBJdzvyN0+J37eNdjUXg3l/BJ5Xu/b1+Y9ZwLgUTg9cwP/trMZ76/vVe+36dV34dTH0/fn/zRl/ecTz4XAAAYVVUj4Akmk2Lt2FYzRT2TLaSzuqWZxpldNp1N06jo2bR1VrCGFM0mD5RESpFSiY1dRRpSUVqUukqMrJRSnqWk/cfO/Wh3d1ly6qSNUla/knb2U8q2ctBbJm3sPt7o2vXkYGcvcXAsPVKOpcWeF+56qSVpSTpMHewkU0ez7qCRFIXGbuu86PylkVYv7HLjcXpI2OnwkMI71YTfE1QUsTYxKIVF1bLTpl7R1aKeHVY2MyyJPTUHZ7E7GZ0U9T7xelbbqakueDzBuTmxdrfdBvvKav2Y7IvM2ekEYV8NP7apXjo1G53WCsTS9VI7iNY+vWJodie2ZSlnmNeqvo2y5p32BBcWxO86g1UtafmyaXVt+vqibRX0RNzOwIGypRwo+0nlsNOyerWlZSlTLGuFdF43TvL2gAHZKlat/PVhrJVLTiOcv2CNciltG6d6+9mbylbiaDclPQjfNIzrx+49dPeROoM55nMHdxaGDeZWs5uDt/XAX415PcH5ebEW6+ro8oVtdbamBnR3ff/A/C1LFadsQHYqavFCH3QaN8bt0DO5mYL663aaG5lyB7fnhzW3GWSztc3tad9r4SNnUFd32m11B9yNae/pjDtYUP7lVNBzDvXNBT2lgcDfwmT9AA8m3cHE3PB428Fa3qrH3eiWamdkNzrd6mx5+rqlud/ploEDdfA5edOg7cwE8njjF0L1RTuSS7VY1O10/ZlO+53MnjnNaI6YG4om+mK9oeJ/G1NdTRo4SI4m3jXB3xBGsyNuKHRXl1zNc+butZR0tsZvaLDTPiM7tEuk5EMl+UhadKp9KoWcWacztBpZcWaTvFo60dN9+0u6fVk2C83cvU3Bt2Jjhqwm26FaWl4/Va2uzbG+YFsFi1JJdSarIVN6RTctZ1K7+RdJbOxd01LrWM2Utx7U1/aT7UV94Cch8CbwV+APZwMAAAAAANwW73tdK976er6gv9DyqlFqvAEX8LgWxOY7XCemepZ33XG5librO4plTS02KvrHXPPezvslU431/ysh8MpZ//8ZeENqAQAAAAC4PT5wrYh9639voHf973nPtST2Lv9dM655sbP8H6tf/xdnfhOcGwAAAAAAt1ttXfAItXgtPndWyC9+HWpZiUbvrYTvrYTuPbfPLjKbydjWYWnD+Gpz7zRvXCRPnyaOrd3Lk91j00zJZuK8knpxmLtIJs0T6+nL9curvWdHh3IqIxtf7lW0g0xlS0s83C7sbcYeXa0Xyvno9vnF/vZ+KlfO5wrxs5Nv8uqTZPbZWTmjroRW7i8tZFWrYMqll7clqHA9qItcNB+3zDVbt+ySbtfX/8IsQwgAAAAAgFE2xfofAAAAAICR1/j8f+AXwbkBAAAAAIBbZ1MYF6r+t18rCMmRiK6Gwmo2pOvyenQ1JMfjckZVdS2i6Vk5lFMjuWhoPR6WY6trufVsPJ6LytEIn/8HAAAAAGD08fl/AAAAAABGH9f/AQAAAAAYfVz/BwAAAABg9HH9HwAAAACA0cf1fwAAAAAARl/z///9LDg3AAAAAABw2yjieNUvyqqak1e1VTkcDmfUWCir5yLRcHZNy0RVOSaH4hlN1fWoFo5qTulaNLYaiodiekRekzN6fG11Yqqx/v9VcG4AAAAAAOD22Ryv+r3/9w0Avv8PAAAAAMDo4/v/AAAAAACMvn8AuNEuugAQAQA=",
      "masterFingerprint": "00000000"
    },
    {
      "network": "testnet",
      "scriptType": "bip49",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "sh(wpkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/49'/1'/0'/0/*))#pzuur0ll",
      "internal": "sh(wpkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/49'/1'/0'/1/*))#8p5ecz5t",
      "accountXpub": "tpubDD7tXK8KeQ3YY83yWq755fHY2JW8Ha8Q765tknUM5rSvjPcGWfUppDFMpQ1ScziKfW3ZNtZvAD7M3u7bSs7HofjTD3KP3YxPK7X6hwV8Rk2",
      "database": "testnet_bip49.sqlite",
      "addresses": {
        "0": "2Mww8dCYPUpKHofjgcXcBCEGmniw9CoaiD2",
        "5": "2N5pTWRLrRdAPGvTd9agPFLFZvPfGNy7xuM",
        "20": "2N64na3M65yZnwAQR5PaKHWgRasFgjUCrj2"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dTW8aRxgH8F1j82KD16laodZKtZYPMZFTL6xh4dCqGDax65fYGNdxqggNy2zYQACza+z0UAl66RfoN6nUtDnl2EP7Efodcsuxw4JZMC9p1YuF/j+BvOwM7DPPzA4eFsvHR3uGRUW9Wn9JLFHmljie574WRY7jXOx+h3ME2H227zHPfZiL+6LxU8B/wC15zjkhKbxd/DnQWvzK/9535f9jgfg/nf984b73F3/Rc+59xgEAAEyrpiF4gqkU3zqzSL5M84VSrkBNrW7UrGqdbdaNBi3kzFrJnFC0lMqoyawqZpNbe6o4oaK4JvaVGAUxqz7JigeP2f1kb29dZHVyRqVAr8Sdg6z6SM0Mlolbe4+3+nYdZnb2k5kzcVc9E9cGXrjvpUJiSDzOZnZS2ZMld9BI8Zy92zwvs980cuTCqtqPcxPCzoUnFN5pJgOeoKryrblRKSwT08rVaYOSMi1MKluclMSBmqOz2J8MJ0WDT7yZ1V5qmqseT3B5mW/d7bXBujK7P7xDkbGdLAjravKx6+SS1bQ7rRuISWmlF0R3H20YmuXEti7qRv1G1esoW74FT3B1lf/RGaykohWrdbNv0z8UbbdgIOJeBjLqQzWjHqTUY6dl7WqhdTFfrmqlXJEaz4vWiAHZLSZm8eYw1qoV1gj2G6xRreQs4yXtPTutPkye7GXFB+Fxw7h97MFD9x/JGcxRvzu4szppMHeb3Rm83QeBZtTnCa6s8K1oX0dXLyzT2Zof0d3t/SPzty42WNmI7DRI+YKOOo3tcTvxTO6koP26TnPleXfw0cqk5naC7LS2s73gf8t9xgZ1c6fXVrfgtqe900V3sKT+y6lg4BwamgsGSgXhPedtH+CB1x1MLk+Otxes6Wt63Ha3NJ2RbXe66Wx5hrqls591y8iBOvqcHDdonZkgMWu/ITRf9SK5JOUytXLtZ7L2s8zWWDM6I2ZM0dxQrGMq/rcx1dekkYPkZO5DE/yYMDodMabQ3Qy5OufM3RspcbZmxzSYtc8oTOwSMbWtpnbFNVbtS1Fis44ztOyssNmkSCrPaW5of4Val9V6qZO76xT8wNszZDPVC9XUivQlMfs2Z4aC7RasiRXCJqsJU3qD1k02qY1/I4nOfGha6h6rk/Lug/ba3ttb1Au/csI74W/hT7YBAAAAAAAAALfFxz7Xhq+9ni/RV1qRGBX7AzjB41rlO59wPa+TWtF1x+UKeds7ylWNlO2KgRnXis/5vGTeXv+/5oTXbP3/l/AOqQUAAAAAAAC4PT5xbfBD63+fMLj+93zkCvGDy3/XomuFd5b/M+3r//ziG47dAAAAAAAAAG6j1hbn4VrJVnLZLK5d1krFte8UWYsWiEQ2NhP3NsL3NqR7z6zaRT6dVqwnu/FdeiSfncXlV6fnSjSqb59FvjmNb5P4kRKLWqXKyX60ftx4cag9OtVParX0w/3aUfhY+97Y1U/lpwfW00YyrezLF0r+2FS2q/qLbFrePZTPrg53lSex4uW38UwpsiFt3A+FVl/UdJKQasptiixsRxY/j1vEjNYsaloVarXX/9wSBhMAAAAAAADANJvH+h8AAAAAAABg6tnf/xd+59gNAAAAAAAAAG6dNDfLNQPStYQsUyKFSUGiNBHfjEgJRUnkCaGarNFCQtKJrG9KcSWciEZierygKPpmYlPG9/8BAAAAAAAAph++/w8AAAAAAAAw/XD9HwAAAAAAAGD64fo/AAAAAAAAwPTD9X8AAAAAAACA6Yfr/wAAAAAAAADTr/P//37j2A0AAAAAAAAAbhuVn20GeEWPFXRK9bgSDdMoodqmrMWlsKZElBiN5MOxSEGhikT0TUkh4Vg4TDWJyrGwHCGFqKTTuXl7/f+GYzcAAAAAAAAAuH3Ss82A7/9+AIC//wcAAAAAAACYfvj7fwAAAAAAAIDp9w+oljooABABAA=="
    },
    {
      "network": "testnet",
      "scriptType": "bip49",
      "xpub": "tpubDD7tXK8KeQ3YY83yWq755fHY2JW8Ha8Q765tknUM5rSvjPcGWfUppDFMpQ1ScziKfW3ZNtZvAD7M3u7bSs7HofjTD3KP3YxPK7X6hwV8Rk2",
      "external": "sh(wpkh([00000000/49'/1'/0']tpubDD7tXK8KeQ3YY83yWq755fHY2JW8Ha8Q765tknUM5rSvjPcGWfUppDFMpQ1ScziKfW3ZNtZvAD7M3u7bSs7HofjTD3KP3YxPK7X6hwV8Rk2/0/*))#w74tvavp",
      "internal": "sh(wpkh([00000000/49'/1'/0']tpubDD7tXK8KeQ3YY83yWq755fHY2JW8Ha8Q765tknUM5rSvjPcGWfUppDFMpQ1ScziKfW3ZNtZvAD7M3u7bSs7HofjTD3KP3YxPK7X6hwV8Rk2/1/*))#mlma5ze7",
      "accountXpub": "tpubDD7tXK8KeQ3YY83yWq755fHY2JW8Ha8Q765tknUM5rSvjPcGWfUppDFMpQ1ScziKfW3ZNtZvAD7M3u7bSs7HofjTD3KP3YxPK7X6hwV8Rk2",
      "database": "testnet_bip49_watch.sqlite",
      "addresses": {
        "0": "2Mww8dCYPUpKHofjgcXcBCEGmniw9CoaiD2",
        "5": "2N5pTWRLrRdAPGvTd9agPFLFZvPfGNy7xuM",
        "20": "2N64na3M65yZnwAQR5PaKHWgRasFgjUCrj2"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dXVMaVxjA8V1REBUxnXaY1klnHS+iGVNBhIWLdoq4idaX+II1ppNhVjgEAgKyK5pcdAZ60y/Qb9KZps1VLnvRfoR+h9z1sstLeBEk7fTGYf6/gXHZc2Cf85yzRw8L4+H+dsYUSqpQOtNNxS/NSLIsfa0okiTZrPsdqc1l3Uc7HsvSh9mkL8o/uqZ2pRnHueSOuN9O/+SqTn819bfzaur3SX3q04nPJ++P/zyVdpyPP5MAABhWlYzb4YlG5eqJqZ/mxGkyG08KI1HKFM1CydosZcoiGTeKWWNA0Uz0QIvENCUWWdvWlAEVlQWloySTVGLak5iy+9i6H21vLylWnXgmnxRXyuZuTHukHXSXKWvbj9c6du0dbO5EDk6ULe1EWeh64Y6XWlQWlcPYwWY0djRj92SislTfbZznrL804vqFWag/jg8IO+4bUHinEnE5PJomV8f6pTCnG2a8JMpCz4nkoLLpQUnsqtk/i53JaKeo+4nXs9pKTWXe4fDMzsrVu602mFdG88d4T2TWTisI82rwsUv6pVWz3mnNQAwh8q0gmvtEOZMw27EtKalM6VrV91FWnZMOz/y8/EN7sOr5RLpQMjo2p3qibRZ0RdzKwIH2UDvQdqPaYbtltWqLS8pprpDIxtMi8zxt9hmQzWLdSF8fxolC3mqE9RdsppCPm5kz0Xr2uvYwcrQdUx74bhrGtWN3H7rzSO3BHJiyezbnBw3mZrMbg7f5wFUJOB2euTm5Gujo6MKFabS3Jvp0d21/3/wtKWWrrE92ynruQvQ7jevjduCZ3EhB7XXbzfVP2D2P5gY1txFko7WN7cmpt9Jn1qCubLbaanfb69Pe8bTdk9X+5VTQdQ71zAVdpW7339J47QAPxu2eyOzgeFvBGs6Kw17vlkp7ZNc73WhvOXq6pbHf6pa+A7X/OXnToG3PBOHR+i+EystWJJd6LifMeO2ZVvutzBatZjRGzA1FYz2x3lDxv42pjib1HSRHYx+a4G8Io9ERNxTaK4u2xjlz91pK2lujNzTYal8mObBLlOiGFt1SFqxqXypea9ZpD616VqzZJK3nn4t4z/68MC8LpWwjd+9T8L1cnyEr0VaoRiItznSjY3OkJ9hmwYKS163JasCUXhYlw5rUbv5FEhj50LTUPFYj5c0HtbX9eGtR7/5Fcr9z/+X+w9oAAAAAAAC3xcdO27Kztp7PipeJtJ7J19+Aczts83LjHa7nJb2Ytt2x2RbHaztyhYSeq1d0jdjmnO33Sybq6//Xkvu1tf7/0/2O1AIAAAAAcHt8YluWe9b/Tnf3+t/xkW1R7l7+26Ztc3J7+T9Su/4vT7+RrBsAAAAAALdRdU1ySNVINTJrpBcui9n0wnfepuXV8L1l371l771nZvHidH1dNZ9shbbEvv/kJOR/eXyuBgKpjZOVb45DG3poXw0GzGz+aCdQOiy/2Es8Ok4dFYvrD3eK+77DxKvMVurY/3TXfFqOrKs7/gv19NBQNwqpF7F1/9ae/+Rqb0t9Ekxffhs6yK4se5fvLy7OX6qrZlkvF29TZL56ZGe5Mz3wSqimMMy8MGvrf2mGwQQAAAAAwDCbYP0PAAAAAMDQq3/+3/2bZN0AAAAAAMCtsy6NShXX++8VeMN+v9C9Pj3pFSIcWl3xhlU1fKrrIuFPiGTYm9L9qVVvSPWFAyvBVCipqqnV8Kqfz/8DAAAAADD8+Pw/AAAAAADDj+v/AAAAAAAMP67/AwAAAAAw/Lj+DwAAAADA8OP6PwAAAAAAw6/x//9+lawbAAAAAAC4bTR5tOKS1VQwmRIiFVIDPhHQRWLVnwh5fQl1RQ2KlVNfcCWpCtWrp1a9qu4L+nwi4RX+oM+/oicD3pQYm6iv/99I1g0AAAAAANw+66MVl/P/vgHA9/8BAAAAABh+fP8fAAAAAIDh9w8Fni7vABABAA==",
      "masterFingerprint": "00000000"
    },
    {
      "network": "testnet",
      "scriptType": "bip84",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "wpkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/84'/1'/0'/0/*)#8xyxaasa",
      "internal": "wpkh(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/84'/1'/0'/1/*)#kjp8qgq9",
      "accountXpub": "tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M",
      "database": "testnet_bip84.sqlite",
      "addresses": {
        "0": "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl",
        "5": "tb1qr7scvm07ta0ldzlrmk7rnmc9lk356yar6zfu45",
        "20": "tb1qgatph3xrdjvcq63xhwct77m2ufn93stn0pwwey"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dy24aVxjA8Rljg7HBOFUr1FqpxvIiduTUXA1TqVUxnjhWiBNjnMSpIjQww0XGYDPjWxaVoJu+QN+kUtN2FXXVRfsIfYfssuxwCRcbSKtuLPT/CZSZOQfmO985c+zDYGVvN1E0dSlXqR6pphQU5gVRFL6RJEEQbNbzltDltp6TPfui8GE24YuzH9yuHWHecSJ4Yp43cz+663Nfu945L1x/zKquT2c+n707/ZOr4DiZfikAADCuakWPwxuPi/UDU82U9Ix2mNZ0I1stHpuVqrVZLZ7pWto4PjRGFM3Hk0ospUip2EZCkUZUlJalnpKiJqWU5ylp57H13E8kViWrTrpY1vQLaXsnpWwpyf4yaSPxeKPn0JPk9qNY8kB6qBxIy31v3PNWK9KKtJdKbsdT+/N2bzEuCs3DxknJ+k0jrZ6aleZ+ekTYaf+Iwlu1mNvhVRSxPjUohSXVMNNV/UxXS7o2qmxuVBL7ag7OYm8yuinqf+HVrHZSU1tyOLwLC2L9dqcN5oXR/mf6WmTWQSsI82L0uavquVWz2WntQAxdL3eCaB/Tz4pZsxvbqpQrVq9UfR9l3Tnr8C4tid93B6tazhYqVaNn03Ut2nZBX8SdDCSV+0pS2Ykre92WNaqtrEqZUiV7mC7oxXzBHDAg28WqUbg6jLOVstUI6zfYYqWcNotHeufVm8r92H4iJd3zDxvGjXP3n7r3TN3BHHbZvdtLowZzu9mtwdvecdfCTod3cVGsh3s6unJqGt2tmQHd3Tg+MH+r0plVNiA7Z2rpVB90GTfH7cgruZWCxvt2mxucsXu3Fkc1txVkq7Wt7VnXG+Eza1DXtjtttXvszWnv2Zzde6j8y6mg7xq6Nhf0lXo874TpxgnuTdu9sYXR8XaCNZw1h73ZLbXuyG52utHdclzrltZxq1sGDtTB1+SwQdudCeTJ5g+E2mUnknO1VNLNdOOVVvutzB5bzWiNmCFFU9diHVLxv42pniYNHCT7Ux+a4IeE0eqIIYX22oqtdc3cvpKS7tbkkAZb7StqI7tEij9Q4g+lZavaV5LPmnW6Q6uZFWs2KajlvJ6+drysm+eV6mErd+9T8J3YnCFr8U6oRragH6lGz+bEtWDbBctSWbUmqxFT+pleNaxJbfgPkvDEh6al9rlaKW/vNNb2051FvednwfPW87fnT2sDAAAAAADcFB87bWvOxnr+UL/MFtRiufkBnMdhWxJbn3Dlq+pxwXbLZluZbhwoVbJqqVnRPWFbdHY/L5lprv9fC57X1vr/L89bUgsAAAAAwM3xiW1NvLb+d3r61/+Oj2wrYv/y3zZnWxS7y/+Jxv1/ce53wXoAAAAAAHCT1b8UHEJdrssL58eHheVvI8FsWFN96lo0dGfNf2fNd+eleXya2YxHj4z7W/rW6Xn54Za8f5yPbD4KZEKbavIkH4zvv1DD+ehZYC+5u/4wtLN3eLGf1yIPjETg+dNnmadHQflyIxZKxC4ujd2YtRd5db67t1vZzevnW8WDFyfVmLxpPAm9yuz6H6351u6uLAXU/Hr5IqvdmKj8jaiOctrReTkfMnXDLOtmY/0vzDOIAAAAAAAYZzOs/wEAAAAAGHvN7/97fhWsBwAAAAAAuHE2hUmh5va9JweDuurzq5pP1+VoKOCTIxE5o6p6NpjVNdmXU4O5kC8a8cvhwHouqkUiuZAcCvL9fwAAAAAAxh/f/wcAAAAAYPxx/x8AAAAAgPHH/X8AAAAAAMYf9/8BAAAAABh/3P8HAAAAAGD8tf7/v18E6wEAAAAAAG4aRZysuUXZJ4dDOTUaXQ+rYX9kXY7kNDmayYYCIetQyBcNqMFoMOvXtfVIIJD1a6qmZ6K+YMYf1LRwxD8101z//yZYDwAAAAAAcPNsTtbczv/7AQB//w8AAAAAwPjj7/8BAAAAABh//wBbRooXABABAA=="
    },
    {
      "network": "testnet",
      "scriptType": "bip84",
      "xpub": "tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M",
      "external": "wpkh([00000000/84'/1'/0']tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M/0/*)#94qtvq0a",
      "internal": "wpkh([00000000/84'/1'/0']tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M/1/*)#5p9234l9",
      "accountXpub": "tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M",
      "database": "testnet_bip84_watch.sqlite",
      "addresses": {
        "0": "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl",
        "5": "tb1qr7scvm07ta0ldzlrmk7rnmc9lk356yar6zfu45",
        "20": "tb1qgatph3xrdjvcq63xhwct77m2ufn93stn0pwwey"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dy24aVxjA8Rljg7HBOFUr1FqpxvIiduTUXA1TqVUxnjhWHCfGOIlTRWhgxgYZA2bG2M6iEnTTF+ibVGrarqKuumgfoe+QXZYdLuFiLmnVjYX+P4E8c86B+c5lDhwG5P29nZypS0fF8qlqSkFhXhBF4RtJEgTBZt1vCR1u6z7ZtS8KH2YTvqj84HbtCvOOM8ET87yZ+9Fdm/va9c556fpjVnV9OvP57N3pn1xZx9n0SwEAgHFVzXkc3nhcrB2aajqvp7WTlKYbmXKuZBbL1mY5V9G1lFE6MUZkzccTSiypSMnYxo4ijSgoLUtdOTlNSirPk9LuY+t+sLOzKlllUrmCpl9K27tJZUtJ9OZJGzuPN7qSniS2H8USh9JD5VBa7nnirqdakVak/WRiO548mLd7c3FRaCQbZ3nrnUZKPTeLjf3UiLBT/hGZt6oxt8OrKGJtalAT5lXDTJX1iq7mdW1U3tyoRuwpObgVuxuj00S9D7zequ2mqS45HN6FBbF2u10H89Jo/Znui8xKtIIwL0cfu6xeWCUbndYKxND1QjuIVppeyWXMTmyr0lGufK3o+yhrzlmHd2lJ/L4zWNVCJlssG12brr5oWxk9EbdbIKHcVxLKblzZ79SsXmxlVUrni5mTVFbPHWfNAQOyla0a2evDOFMsWJWw3sHmioWUmTvV24/eVO7HDnaS0j3/sGFcP3bvobuP1BnMYZfdu700ajC3qt0cvK0ddzXsdHgXF8VauKuji+em0dmaGdDd9fSB7bcqVay8Aa1TUfPn+qDTuDFuR57JzSaoP2+nusEZu3drcVR1m0E2a9vcnnW9ET6zBnV1u11Xu8femPaezdm9J8q/nAp6zqG+uaAn1+N5J0zXD3Bv2u6NLYyOtx2s4aw67I1uqXZGdqPTjc6Wo69bmulWtwwcqIPPyWGDtjMTyJONF4TqVTuSCzWf181U/ZFW/a2WLVnVaI6YIVlTfbEOKfjfxlRXlQYOkoOpD03wQ8JodsSQTHt1xdY8Z25fa5LO1uSQClv1y2kju0SKP1DiD6Vlq9hXks+adTpDq9Eq1mySVQvHeqovvaCbF8XySbPt3jfBd2JjhqzG26Eamax+qhpdmxN9wbYylqWCak1WI6b0il42rElt+AtJeOJD01LrWM0mb+3U1/bT7UW952fB89bzt+dPawMAAAAAANwUHztta876ev5Ev8pk1Vyh8QGcx2FbEpufcB2X1VLWdstmW5muJ+SLGTXfKOiesC06O5+XzDTW/68Fz2tr/f+X5y1NCwAAAADAzfGJbU3sW/87Pb3rf8dHthWxd/lvm7Mtip3l/0T9+r8497tg3QAAAAAAuMlqXwoOoSbX5IWL0kl2+Vtfy1o0dGfNf2fNd+elWTpPb8ajp8b9LX3r/KLwcEs+KB1HNh8F0qFNNXF2HIwfvFDDx9FKYD+xt/4wtLt/cnlwrEUeGDuB50+fpZ+eBuWrjVhoJ3Z5ZezFrL3Iq4u9/b3i3rF+sZU7fHFWjsmbxpPQq/Se/9Gab+3uypIcOjMrZz71xkTlr0cVLsmBYCgvm7phFnSzvv4X5hlEAAAAAACMsxnW/wAAAAAAjL3G9/89vwrWDQAAAAAA3DibwqRQdb//WYFPDgZ11edXNZ+uy9FQwCdHInJaVfVMMKNrsu9IDR6FfNGIXw4H1o+iWiRyFJJDQb7/DwAAAADA+OP7/wAAAAAAjD+u/wMAAAAAMP64/g8AAAAAwPjj+j8AAAAAAOOP6/8AAAAAAIy/5v//+0WwbgAAAAAA4KZRxMmqW5R9cjh0pEaj62E17I+sy5EjTY6mM6FAyEoK+aIBNRgNZvy6th4JBDJ+TdX0dNQXTPuDmhaO+KdmGuv/3wTrBgAAAAAAbp7Nyarb+X8/AOD3/wAAAAAAjD9+/w8AAAAAwPj7B/SlqIQAEAEA",
      "masterFingerprint": "00000000"
    },
    {
      "network": "testnet",
      "scriptType": "bip86",
      "mnemonic": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
      "external": "tr(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/86'/1'/0'/0/*)#wyu7eln9",
      "internal": "tr(tprv8ZgxMBicQKsPe5YMU9gHen4Ez3ApihUfykaqUorj9t6FDqy3nP6eoXiAo2ssvpAjoLroQxHqr3R5nE3a5dU3DHTjTgJDd7zrbniJr6nrCzd/86'/1'/0'/1/*)#lsely2ra",
      "accountXpub": "tpubDDfvzhdVV4unsoKt5aE6dcsNsfeWbTgmLZPi8LQDYU2xixrYemMfWJ3BaVneH3u7DBQePdTwhpybaKRU95pi6PMUtLPBJLVQRpzEnjfjZzX",
      "database": "testnet_bip86.sqlite",
      "addresses": {
        "0": "tb1p8wpt9v4frpf3tkn0srd97pksgsxc5hs52lafxwru9kgeephvs7rqlqt9zj",
        "5": "tb1ptwu02r7yxyffs6440gdntnjhgv75syk20nwawp2khgas38ztks9qdn6ztw",
        "20": "tb1pw0mxf20gyzq7cuc3rzc5n5juuad8l6299cwgehdcrp7ljkujep9sy38dw6"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dTU8bRxjA8V0MNgaMSdXKalGqRRwCESlrjN8OrQpmk5A4BBxDQqrIWttjvMHYxLsYyKGS3Uu/QL9JpabtKaeqh/Yj9Dvk1mPXL/ELGKdVL8j6/2SL9c7Y+8wzs2PGa8STnbhhCSVXKh/plhKQZiRZlr5WFEmSHPb9htThse+jXY9l6cMc0heV7z1TW9KM65XkXfO+nf7BU5v+aupv99nU75P61KcTn0/eHv9xKu96Nf5CAgBgWFUNr8sXi8m1fUtPF0Q6e5jKCjNTNo6tUtneLBsVkU2Zx4fmgKKZWEJbS2pKcm09rikDKioLSleJkVWS2rOksvXYvu/G40uKXSdlFLPiTNncSmr3tERvmbIef7zetWs7sfloLbGvPNT2lYWeF+56qUVlUXmSTGzGkrszTp8Rk6XGbvNVwf5NI6WfWKXG49SAsFP+AYU3qmsel0/T5NpYvxQWdNNKlUVF6AWRHVQ2PSiJPTX7Z7E7GZ0U9T7xYlbbqanOu1y+2Vm5drPdBuvMbP0YvxSZvdMOwjobfOyyfmrXbHRaKxBTiGI7iNY+UTEyVie2JSVnlC9UfR9lzT3p8s3Py991BqtezORLZbNrc+pStK2CnojbGUhod7WEthXTnnRaVq+2uKSkC6XMYSovjIO81WdAtop1M39xGGdKRbsR9m+wRqmYsowj0X72hnZ3bTeeVO74rxrG9WP3Hrr7SJ3BHJxy+jbnBw3mVrObg7f1wFMNul2+uTm5Fuzq6NKJZXa2Jvp0d31/3/wtKRW7rE92KnrhRPQ7jRvjduCZ3ExB/XU7zQ1MOH335gY1txlks7XN7cmpt9Jn9qCubrbb6vQ6G9Pe02mn71D7l1NBzzl0aS7oKfV6/5bG6we4M+70rc0OjrcdrOmuupyNbql2Rnaj083OlutStzT3293Sd6D2PyevGrSdmSA62nhDqJ63IznVCwVhperPtNtvZ/bYbkZzxFxRNHYp1isq/rcx1dWkvoNkd+xDE/wVYTQ74opCZ3XR0Txnbl5ISWdr9IoG2+0zsgO7RInd12IPlQW72peKas86naHVyIo9m+T14oFIXdpfFNZpqXzYzN37FHwrN2bIaqwdqpnJiyPd7NocuRRsq2BBKer2ZDVgSq+IsmlPale/kQRHPjQttY7VTHnrQX1tP95e1Ht/krzvvH95/7A3AAAAAADAdfGx27Hsrq/nD8V5Jq8bxcYHcF6XY15ufsJ1UNaP844bDsfieH1HoZTRC42KnhHHnLvzeclEY/3/RvK+sdf/f3rfkVoAAAAAAK6PTxzL8qX1v9vbu/53feRYlHuX/45px5zcWf6P1K//y9O/SfYNAAAAAIDrrhaSXFItWAvOWuWFb8KBTDCrq/pyJHRr2X9rWb31wjo+SW9s5Cqv89m9vdWToll6aAV1LZTNmFtmTjxNJw+O4s+3jUh8Z2N/d+XMOCvvi6NHuacPAuv6XlHcD5yEN9Z3xHY2eZo/Pk/rDxO70eCxEdp+tGvFt9cfxPd2EsevteLL3Mvnr58tq8u3F+dXzaOX+XA2eE1i8tdjOj8PF1csvWIJ0yoKq77+l2YYQAAAAAAADLMJ1v8AAAAAAAy9xvf/vb9I9g0AAAAAAFw7G9KoVPWo70UDAaGrfj2rChGNrK6o0XA4mtZ1kQlkRDaq5vRAblWNhP3R4EooF8mGw7nV6GqA7/8DAAAAADD8+P4/AAAAAADDj+v/AAAAAAAMP67/AwAAAAAw/Lj+DwAAAADA8OP6PwAAAAAAw6/5//9+luwbAAAAAAC4bjR5tOqRI2owEg5Egmo4FFFzgVAuHAr5VTWaC2dVfzoTFGo4Es3pGbGi65F0OugPRHNqYDUcioaiK+lAeGyisf7/VbJvAAAAAADg+tkYrXrc//cDAP7+HwAAAACA4cff/wMAAAAAMPz+AZj4UpUAEAEA"
    },
    {
      "network": "testnet",
      "scriptType": "bip86",
      "xpub": "tpubDDfvzhdVV4unsoKt5aE6dcsNsfeWbTgmLZPi8LQDYU2xixrYemMfWJ3BaVneH3u7DBQePdTwhpybaKRU95pi6PMUtLPBJLVQRpzEnjfjZzX",
      "external": "tr([00000000/86'/1'/0']tpubDDfvzhdVV4unsoKt5aE6dcsNsfeWbTgmLZPi8LQDYU2xixrYemMfWJ3BaVneH3u7DBQePdTwhpybaKRU95pi6PMUtLPBJLVQRpzEnjfjZzX/0/*)#46vtzem5",
      "internal": "tr([00000000/86'/1'/0']tpubDDfvzhdVV4unsoKt5aE6dcsNsfeWbTgmLZPi8LQDYU2xixrYemMfWJ3BaVneH3u7DBQePdTwhpybaKRU95pi6PMUtLPBJLVQRpzEnjfjZzX/1/*)#ywf2lvtv",
      "accountXpub": "tpubDDfvzhdVV4unsoKt5aE6dcsNsfeWbTgmLZPi8LQDYU2xixrYemMfWJ3BaVneH3u7DBQePdTwhpybaKRU95pi6PMUtLPBJLVQRpzEnjfjZzX",
      "database": "testnet_bip86_watch.sqlite",
      "addresses": {
        "0": "tb1p8wpt9v4frpf3tkn0srd97pksgsxc5hs52lafxwru9kgeephvs7rqlqt9zj",
        "5": "tb1ptwu02r7yxyffs6440gdntnjhgv75syk20nwawp2khgas38ztks9qdn6ztw",
        "20": "tb1pw0mxf20gyzq7cuc3rzc5n5juuad8l6299cwgehdcrp7ljkujep9sy38dw6"
      },
      "databaseGzipBase64": "H4sIAAAAAAAC/+3dXVMaVxjA8V1REBUxnXaY1klnHS+imaQuIm8X7VRxkxiJUYImppNhFjiEjQiGXdHkojPQm36BfpPONG2vctXpRfsR+h1y18suL+FFgbTTG4f5/wbGZc+Bfc5zzh49LIyP9uKGJZRcqXysW0pAmpNkWfpaUSRJctj3a1KHx76Pdz2WpQ9zSF9UvvfM7EhzrpeSd937dvYHT232q5m/3eczv0/rM59OfT59c/LHmbzr5eQzCQCAUVU1vC5fLCbXDi09XRDp7FEqK8xM2TixSmV7s2xURDZlnhyZQ4rmYgltPakpyfWNuKYMqagsKV0lRlZJak+Sys5D+74fj99S7Dopo5gV58rWTlK7qyV6y5SN+MONrl27ia0H64lDZVs7VJZ6XrjrpZaVZeVRMrEVS+7POX1GTJYau82XBfsvjZR+apUaj1NDwk75hxReq657XD5Nk2sT/VJY0E0rVRYVoRdEdljZ7LAk9tTsn8XuZHRS1PvEi1ltp6a66HL55ufl2vV2G6xzs/Vj8lJk9k47COt8+LHL+plds9FprUBMIYrtIFr7RMXIWJ3Ybik5o3yh6vsoa+5pl29xUf6uM1j1YiZfKptdmzOXom0V9ETczkBCu6MltJ2Y9qjTsnq15VtKulDKHKXywniet/oMyFaxbuYvDuNMqWg3wv4L1igVU5ZxLNrP3tTurO/Hk8pt/6BhXD9276G7j9QZzMEZp29rcdhgbjW7OXhbDzzVoNvlW1iQa8Guji6dWmZna6pPd9f3983fLaVil/XJTkUvnIp+p3Fj3A49k5spqL9up7mBKafv7sKw5jaDbLa2uT0981b6zB7U1a12W51eZ2Paezzr9B1p/3Iq6DmHLs0FPaVe79/SZP0AtyedvvX54fG2gzXdVZez0S3VzshudLrZ2XJd6pbmfrtb+g7U/ufkoEHbmQmi441fCNVX7UjO9EJBWKn6M+3225k9sZvRHDEDiiYuxTqg4n8bU11N6jtI9ic+NMEPCKPZEQMKndVlR/OcuX4hJZ2t8QENtttnZId2iRK7p8W2lSW72peKas86naHVyIo9m+T14nORurS/KKyzUvmombv3KfhWbsyQ1Vg7VDOTF8e62bU5dinYVsGSUtTtyWrIlF4RZdOe1Ab/IgmOfWhaah2rmfLWg/rafrK9qPf+JHnfef/y/mFvAAAAAACAq+Jjt2PFXV/PH4lXmbxuFBtvwHldjkW5+Q7X87J+kndccziWJ+s7CqWMXmhU9Iw5Ftyd90umGuv/N5L3jb3+/9P7jtQCAAAAAHB1fOJYkS+t/93e3vW/6yPHsty7/HfMOhbkzvJ/rH79X579TbJvAAAAAABcdbWQ5JJqwVpw3iovfaO2rERCN1b8N1bUG8+sk9P05mau8jqfPThYOy2apW0rqGuhbMbcMXPicTr5/Dj+dNeIxPc2D/dXz43z8qE4fpB7fD+woR8Uxb3AaXhzY0/sZpNn+ZNXaX07sR8Nnhih3Qf7Vnx34378YC9x8lorvsi9ePr6yYq6cnN5cS1UsV6L4+AViclfj+nVWW61ULEqljCtorDq639pjgEEAAAAAMAom2L9DwAAAADAyGt8/t/7i2TfAAAAAADAlbMpjUtVz/uvFajRQEDoql/PqkJEI2urajQcjqZ1XWQCGZGNqjk9kFtTI2F/NLgaykWy4XBuLboW4PP/AAAAAACMPj7/DwAAAADA6OP6PwAAAAAAo4/r/wAAAAAAjD6u/wMAAAAAMPq4/g8AAAAAwOhr/v+/nyX7BgAAAAAArhpNHq965IgajIQDkaAaDkXUXCCUC4dCflWN5sJZ1Z/OBIUajkRzekas6noknQ76A9GcGlgLh6Kh6Go6EJ6Yaqz/f5XsGwAAAAAAuHo2x6se9/99A4Dv/wMAAAAAMPr4/j8AAAAAAKPvH/Sfc14AEAEA",
      "masterFingerprint": "00000000"
    }
  ]
}
''';
