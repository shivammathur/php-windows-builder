<?php

error_reporting(E_ALL);
date_default_timezone_set('UTC');

set_error_handler(function ($code, $message) {
    throw new Exception($message, $code);
});

for ($i = 0; $i < 4096; $i++) {
    try {
        eval('class PgoDateTime' . $i . ' extends DateTime { public function getTimezone() {} public function getTimestamp() {} }');
    } catch (Exception $e) {
    }

    try {
        eval('class PgoSerializable' . $i . ' implements Serializable { public function serialize() {} public function unserialize($serialized) {} }');
    } catch (Exception $e) {
    }
}

restore_error_handler();

set_error_handler(function ($code, $message) {
    new class extends DateTime {
    };
});

for ($i = 0; $i < 1024; $i++) {
    new class extends DateTime {
        public function getTimezone() {}
    };
}
