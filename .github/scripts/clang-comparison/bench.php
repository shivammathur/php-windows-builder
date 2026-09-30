<?php
function mix(int $n): int { return (($n * 17) ^ ($n >> 3)) & 0x7fffffff; }
final class Counter { public int $value = 0; public function bump(int $n): void { $this->value = ($this->value + $n) % 1000003; } }
$tests = [
    'integer_calls' => static function () { $n = 1; for ($i=0; $i<3000000; $i++) $n = mix($n % 10000000); return $n; },
    'objects' => static function () { $o = new Counter; for ($i=0; $i<3000000; $i++) $o->bump($i % 100); return $o->value; },
    'arrays' => static function () { $v = 0; for ($k=0; $k<3000; $k++) { $a=range(1,1000); $a=array_map(static fn($x)=>($x*17)%997,$a); sort($a); $v+=array_sum($a); } return $v; },
    'json' => static function () { $a=['items'=>array_fill(0,40,['id'=>123,'name'=>'PHP Windows build','ok'=>true,'tags'=>['alpha','beta']])]; $v=0; for($i=0;$i<20000;$i++) $v+=count(json_decode(json_encode($a, JSON_THROW_ON_ERROR),true,512,JSON_THROW_ON_ERROR)['items']); return $v; },
    'strings_regex' => static function () { $s=str_repeat('The quick brown fox jumps over 123 lazy dogs. ',40); $v=0; for($i=0;$i<30000;$i++){ $t=preg_replace('/\b([a-z]+)\s+(\d+)/i','$2:$1',$s); $v+=strlen(str_replace('fox','PHP',$t)); } return $v; },
    'hash' => static function () { $s=str_repeat('php-windows-builder',100); for($i=0;$i<40000;$i++) $s=hash('sha256',$s,true).substr($s,32); return bin2hex(substr($s,0,32)); },
];
$name=$argv[1]; $repeat=max(1,(int)($argv[2] ?? 1)); $start=hrtime(true);
for ($r=0; $r<$repeat; $r++) $result=$tests[$name]();
$seconds=(hrtime(true)-$start)/1e9/$repeat;
echo json_encode(['name'=>$name,'seconds'=>$seconds,'checksum'=>hash('sha256',serialize($result))],JSON_THROW_ON_ERROR),"\n";
