extends Node
## 迷宫里的怪物同时最多有 MAX_LOADED 个的模型留在内存里。
## 怪物平时只是一个没有模型的空节点（只有计时和行为），快出场时（PREFETCH 秒前）在后台线程里加载模型，
## 出场时向这里要一个名额：名额满了、或者模型还没加载完，就晚一点再试；退场后过了 KEEP 秒（而且不会马上又出来）
## 把模型释放、还回名额。模型路径用字符串，不用 preload——preload 会让模型一直留在内存里。

const MAX_LOADED := 2            # 同时留在内存里的怪物模型最多几个
const PREFETCH := 6.0            # 出场前多久开始在后台加载（秒）
const KEEP := 30.0               # 退场后模型再留多久才释放（马上又要出来就不用重新加载）

var holders: Array[Node] = []    # 正占着名额的怪物
var requested := {}              # 已经在后台加载的模型路径


## 快要出场了：在后台线程里先把模型读进来
func prefetch(path: String) -> void:
	if not requested.has(path):
		requested[path] = true
		ResourceLoader.load_threaded_request(path)


## 出场：拿名额和模型。名额满了或者还没加载完返回 null（晚一点再试）；拿到以后由怪物自己实例化
func take(who: Node, path: String) -> PackedScene:
	if who not in holders and holders.size() >= MAX_LOADED:
		return null
	prefetch(path)
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	var scene: PackedScene = ResourceLoader.load_threaded_get(path)
	requested.erase(path)
	if who not in holders:
		holders.append(who)
	return scene


## 模型释放了：还回名额
func release(who: Node) -> void:
	holders.erase(who)
