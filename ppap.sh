#!/bin/bash
# フォルダ一括パスワード付きZIP圧縮ツール（Mac / Linux版）
# 使い方: 圧縮したいフォルダと同じフォルダにこのファイルを置き、bash ppap.sh で実行します

# ==========================================
# 設定項目
# ==========================================
# 自動生成するパスワードの文字数
PASS_LENGTH=12

# 暗号化方式
#   ZipCrypto : 標準の zip コマンドで圧縮します。Windows標準のエクスプローラーで解凍できます。
#   AES256    : 7-Zip（7zz / 7z / 7za コマンド）で圧縮します。解凍側にも7-Zip等が必要です。
ENCRYPTION=ZipCrypto
# ==========================================

set -u

# 判別しづらい 1 / l / I / 0 / O を除いた文字
CHARS='abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'

# 圧縮コマンドの確認
case "$ENCRYPTION" in
  ZipCrypto)
    if ! command -v zip > /dev/null 2>&1; then
      echo "[エラー] zip コマンドが見つかりません。"
      echo "Linuxの場合は、パッケージマネージャーで zip をインストールしてください（例: sudo apt install zip）。"
      exit 1
    fi
    ;;
  AES256)
    SEVEN_ZIP=""
    for c in 7zz 7z 7za; do
      if command -v "$c" > /dev/null 2>&1; then SEVEN_ZIP="$c"; break; fi
    done
    if [ -z "$SEVEN_ZIP" ]; then
      echo "[エラー] AES256 には 7-Zip が必要ですが、見つかりません（7zz / 7z / 7za）。"
      echo "Macの場合は brew install sevenzip、Linuxの場合は sudo apt install p7zip-full などでインストールしてください。"
      exit 1
    fi
    ;;
  *)
    echo "[エラー] ENCRYPTION の値が正しくありません: $ENCRYPTION（ZipCrypto または AES256）"
    exit 1
    ;;
esac

# 対象フォルダ（このスクリプトが置かれているフォルダ）
TARGET_DIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo "処理を開始します..."
echo "対象フォルダ: $TARGET_DIR"
echo

# パスワード生成
gen_pass() {
  LC_ALL=C tr -dc "$CHARS" < /dev/urandom | head -c "$PASS_LENGTH"
}

# CSV用に値を "..." で囲む（中の " は "" にする）
csv_field() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"
}

# ZIP内の日本語ファイル名をWindowsで文字化けしない形に補正する
#   - ファイル名をNFC（Macの濁点分離をWindowsと同じ形）にそろえる
#   - UTF-8で記録されていることを示すフラグを付ける
fix_zip_names() {
  perl -e '
use strict; use warnings;
use Encode qw(decode encode); use Unicode::Normalize qw(NFC);
my $f = shift;
open my $in, "<:raw", $f or die; my $d = do { local $/; <$in> }; close $in;
my $e = rindex($d, "PK\x05\x06"); die "no eocd\n" if $e < 0;
my (undef, undef, undef, undef, $cnt, $cdsize, $cdoff, $clen) = unpack("V v v v v V V v", substr($d, $e, 22));
die "zip64\n" if $cnt == 0xFFFF || $cdoff == 0xFFFFFFFF;
my $comment = substr($d, $e + 22, $clen);
my ($out, $cd, $p) = ("", "", $cdoff);
for (1 .. $cnt) {
  die "bad cd\n" unless substr($d, $p, 4) eq "PK\x01\x02";
  my @h = unpack("V v v v v v v V V V v v v v v V V", substr($d, $p, 46));
  my ($nlen, $elen, $klen, $loff, $csize) = @h[10, 11, 12, 16, 8];
  die "zip64\n" if $csize == 0xFFFFFFFF || $loff == 0xFFFFFFFF;
  my $name  = substr($d, $p + 46, $nlen);
  my $cext  = substr($d, $p + 46 + $nlen, $elen);
  my $ccom  = substr($d, $p + 46 + $nlen + $elen, $klen);
  $p += 46 + $nlen + $elen + $klen;
  die "bad local\n" unless substr($d, $loff, 4) eq "PK\x03\x04";
  my @l = unpack("V v v v v v V V V v v", substr($d, $loff, 30));
  my $lext  = substr($d, $loff + 30 + $l[9], $l[10]);
  my $start = $loff + 30 + $l[9] + $l[10];
  my $len   = $csize;
  if ($l[2] & 8) { $len += substr($d, $start + $csize, 4) eq "PK\x07\x08" ? 16 : 12; }
  my $body  = substr($d, $start, $len);
  if ($name =~ /[\x80-\xFF]/) {
    my $u = eval { decode("UTF-8", $name, Encode::FB_CROAK | Encode::LEAVE_SRC) };
    if (defined $u) { $name = encode("UTF-8", NFC($u)); $h[3] |= 0x800; $l[2] |= 0x800; }
  }
  $l[9] = $h[10] = length $name;
  $h[16] = length $out;
  $out .= pack("V v v v v v V V V v v", @l) . $name . $lext . $body;
  $cd  .= pack("V v v v v v v V V V v v v v v V V", @h) . $name . $cext . $ccom;
}
$out .= $cd . pack("V v v v v V V v", 0x06054b50, 0, 0, $cnt, $cnt, length $cd, length $out, length $comment) . $comment;
open my $o, ">:raw", "$f.tmp" or die; print $o $out; close $o or die;
rename "$f.tmp", $f or die;
' "$1" 2> /dev/null || { rm -f "$1.tmp"; return 1; }
}

if ! perl -MEncode -MUnicode::Normalize -e 1 > /dev/null 2>&1; then
  echo "[注意] perl が見つからないため、日本語ファイル名の補正を行いません（Windowsで文字化けする場合があります）。"
  echo
  NO_PERL=1
else
  NO_PERL=0
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
CSV_PATH="$TARGET_DIR/password_list_$TIMESTAMP.csv"
CSV_ROWS=""
FOUND=0

for dir in "$TARGET_DIR"/*/; do
  [ -d "$dir" ] || continue
  [ -L "${dir%/}" ] && continue
  FOUND=1
  name="$(basename "$dir")"

  # 中身が空（macOSの .DS_Store のみの場合も含む）ならスキップ
  if [ -z "$(find "$dir" -mindepth 1 ! -name '.DS_Store' -print -quit)" ]; then
    echo "[スキップ] 中身が空のため除外: $name"
    continue
  fi

  pass="$(gen_pass)"
  zip_name="$name.zip"
  zip_path="$TARGET_DIR/$zip_name"
  rm -f "$zip_path"

  if [ "$ENCRYPTION" = "AES256" ]; then
    (cd "$dir" && "$SEVEN_ZIP" a -tzip -p"$pass" -mem=AES256 -xr'!.DS_Store' "$zip_path" . > /dev/null)
  else
    (cd "$dir" && zip -r -q -P "$pass" "$zip_path" . -x '.DS_Store' '*/.DS_Store')
  fi

  if [ $? -eq 0 ]; then
    if [ "$NO_PERL" -eq 0 ] && ! fix_zip_names "$zip_path"; then
      echo "[注意] ファイル名の補正に失敗しました（ZIP自体は作成済み）: $zip_name"
    fi
    echo "[完了] $zip_name"
    CSV_ROWS="$CSV_ROWS$(csv_field "$zip_name"),$(csv_field "$pass")"$'\r\n'
  else
    echo "[失敗] $zip_name"
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "処理対象のサブフォルダが見つかりませんでした。"
fi

if [ -n "$CSV_ROWS" ]; then
  # UTF-8 BOM付き（Excelで文字化けしないように）
  {
    printf '\xEF\xBB\xBF'
    printf '"ファイル名","パスワード"\r\n'
    printf '%s' "$CSV_ROWS"
  } > "$CSV_PATH"
  echo
  echo "CSVファイルを出力しました: $CSV_PATH"
fi

echo
echo "すべての処理が終了しました。"
