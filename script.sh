#!/bin/bash
set -e


DEPS=( echo rm curl gm tesseract xmllint sed tr )

for i in "${DEPS[@]}"; do
	if ! hash $i 2>/dev/null; then
		echo -e "$i not installed!"
		exit 1
	fi
done

if [ $# -lt 4 ]; then
  echo "Número de parámetros incorrecto. Ejemplo:"
  echo "$0 X1234567X R500001 2018 email1@gmail.com email2@hotmail.com"
  echo "$0 X1234567X R500001 2015 0 email1@gmail.com email2@hotmail.com"
  exit 1
fi

nie=$1
num=$2
year=$3
orden=$4

touch md5-$nie.sum

if [[ "$orden" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
	emails="${@:4}"
else
	emails="${@:5}"
fi

send_email() {

  echo -e "$1" | ssmtp $emails
  #echo -e "$emails"
  #echo -e "$1"
}


execute() {

curl --request GET \
  -s \
  --url https://sede.mjusticia.gob.es/eConsultas/inicioNacionalidad  \
  --cookie-jar nada.txt \
    >/dev/null


captcha=$(curl --request GET \
  -s \
  --url https://sede.mjusticia.gob.es/eConsultas/jcaptcha_image.action  \
  --cookie-jar nada.txt \
  --cookie nada.txt \
  --output - | \
gm convert \
  - \
  -fuzz 100% \
  -opaque yellow \
  -fill white \
  - | gm convert - -fuzz 20% -fill white -opaque black - \
| tesseract \
  - \
  stdout \
  -l spa | \
head -1)

for i in "${PIPESTATUS[@]}"; do
  if [[ $i -ne 0 ]]; then
    send_email "Error críticio en procesar el captcha"
    exit 1
  fi
done

# echo $captcha
#
# set -x

HTML=$(curl --request POST \
  -s \
  --url https://sede.mjusticia.gob.es/eConsultas/inicioNacionalidad  \
  -d "formuNac.codigoNieCompleto=$nie&formuNac.numero=$num&formuNac.yearSolicitud=$year&formuNac.numOrden=$orden&jCaptchaResponse=$captcha&action:enviarDatosNacionalidad=Submit%2BQuery"  \
  --cookie-jar nada.txt \
  --cookie nada.txt)

rm nada.txt
}



execute
z=1
while echo "$HTML" | grep -qi "los siguientes errores"; do
  if [ $z -gt 20 ]; then
  	send_email "Error. Más de 20 intentos sin resolver el captcha"
  	exit 1
  fi
  let z=$z+1
  echo "intento nº $z"
  execute
done

estado=$(echo "$HTML" | xmllint --html --xpath "//div[contains(@class, 'bloqueCampoTextoInformativo')]/p" - 2>/dev/null | sed -e 's/^[ \t]*//')
actual_md5=$(echo "$estado" | md5sum | awk '{print $1}')

# echo $actual_md5

if [[ ! $actual_md5 = $(cat md5-$nie.sum) ]]; then
    echo "BINGO"
    send_email "Subject: NACIONALIDAD\r\nContent-Type: text/html; charset=\"UTF-8\"\r\nAlgo ha cambiado... Revisa!.\nRaw Output:\n$estado"
    echo $actual_md5 > md5-$nie.sum
else
  echo "nop, nada..."
fi
