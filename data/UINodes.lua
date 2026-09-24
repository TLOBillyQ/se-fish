---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT

return {
	-- 树状结构声明：
	-- 节点 = {name, type} 或 {name, type, {子节点...}}
	--   [1] name = 节点名
	--   [2] type = SE SDK 运行时类名
	--   [3] children = 子节点数组（叶子节点省略）
	{"ScreenMain", "EUILayout", {
		{"ImageCoin", "EUIImage"},
		{"LabelCoin", "EUITextLabel"},
	}},
	{"ScreenShop", "EUILayout", {
		{"ShopRootBG", "EUIImage", {
			{"ShopRoot", "EUIImage", {
				{"ShopItemIcon2", "EUIImage"},
				{"ShopItemName2", "EUITextLabel"},
				{"ShopItemIcon1", "EUIImage"},
				{"ShopItemName1", "EUITextLabel"},
				{"BtnShopBuy1", "EUIButton", {
					{"ShopPriceCoin1", "EUIImage"},
					{"LabelShopPrice1", "EUITextLabel"},
				}},
				{"BtnShopBuy2", "EUIButton", {
					{"ShopPriceCoin2", "EUIImage"},
					{"LabelShopPrice2", "EUITextLabel"},
				}},
				{"Coin_3", "EUIImage"},
				{"LabelCurCoin", "EUITextLabel"},
				{"BtnShopClose", "EUIButton"},
				{"LabelShopTitle", "EUITextLabel"},
			}},
		}},
	}},
	{"DialogNoticeConfirm", "EUILayout", {
		{"BG", "EUIImage", {
			{"UIList", "EUIListView", {
				{"BtnYes", "EUIButton"},
				{"BtnNo", "EUIButton"},
			}},
			{"LabelText", "EUITextLabel"},
		}},
	}},
	{"ScreenMsg", "EUILayout", {
		{"ItemMsg", "EUIImage", {
			{"BG", "EUIImage"},
			{"LabelMsg", "EUITextLabel"},
		}},
	}},
	{"SceneNodeShop", "EUISceneNode", {
		{"LabelShopTitle", "EUITextLabel"},
	}},
	{"SceneNodeFish", "EUISceneNode", {
		{"LabelFishTitle", "EUITextLabel"},
	}},
}
