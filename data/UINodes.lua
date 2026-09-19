---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT

return {
	-- 树状结构声明：
	-- 节点 = {name, type} 或 {name, type, {子节点...}}
	--   [1] name = 节点名
	--   [2] type = SE SDK 运行时类名
	--   [3] children = 子节点数组（叶子节点省略）
	{"ScreenMain", "EUILayout", {
		{"BtnFishEnter", "EUIImage", {
			{"LabelBtnFish", "EUITextLabel"},
			{"UFXFish", "EUINodeBase"},
		}},
		{"ImageCoin", "EUIImage"},
		{"LabelCoin", "EUITextLabel"},
	}},
	{"ScreenShop", "EUILayout", {
		{"ShopRootBG", "EUIImage", {
			{"ShopRoot", "EUIImage", {
				{"ImageFishLv", "EUIImage"},
				{"LabelFishLv", "EUITextLabel"},
				{"ImageRodLv", "EUIImage"},
				{"LabelRodLv", "EUITextLabel"},
				{"ListRodLv", "EUIListView", {
					{"1", "EUIImage"},
					{"2", "EUIImage"},
					{"3", "EUIImage"},
					{"4", "EUIImage"},
					{"5", "EUIImage"},
				}},
				{"ListFishLv", "EUIListView", {
					{"1", "EUIImage"},
					{"2", "EUIImage"},
					{"3", "EUIImage"},
					{"4", "EUIImage"},
					{"5", "EUIImage"},
				}},
				{"BtnRodLvUp", "EUIButton", {
					{"Coin_1", "EUIImage"},
					{"LabelRodLvUpCost", "EUITextLabel"},
				}},
				{"BtnFishLvUp", "EUIButton", {
					{"Coin_2", "EUIImage"},
					{"LabelFishLvUpCost", "EUITextLabel"},
				}},
				{"LabelRodLvMax", "EUITextLabel"},
				{"LabelFishLvMax", "EUITextLabel"},
				{"Coin_3", "EUIImage"},
				{"LabelCurCoin", "EUITextLabel"},
				{"BtnShopClose", "EUIButton"},
				{"LabelShopTitle", "EUITextLabel"},
				{"BtnResetGM", "EUIButton"},
				{"LabelGMTips", "EUITextLabel"},
			}},
		}},
	}},
	{"ScreenFishing", "EUILayout", {
		{"Bg", "EUIImage"},
		{"BtnClose", "EUIButton"},
		{"Btn1", "EUIButton", {
			{"MarkNum1", "EUIImage"},
		}},
		{"Btn2", "EUIButton", {
			{"MarkNum2", "EUIImage"},
		}},
		{"Btn3", "EUIButton", {
			{"MarkNum3", "EUIImage"},
		}},
		{"Btn4", "EUIButton", {
			{"MarkNum4", "EUIImage"},
		}},
		{"Btn5", "EUIButton", {
			{"MarkNum5", "EUIImage"},
		}},
		{"Btn6", "EUIButton", {
			{"MarkNum6", "EUIImage"},
		}},
		{"ProcessBg", "EUIImage", {
			{"ProcessBar", "EUIImage"},
		}},
		{"LabelTips", "EUITextLabel"},
		{"FrameNumsArea", "EUIImage"},
		{"ProgressRoot", "EUINodeBase", {
			{"progress_bar_bg", "EUIImage"},
			{"clipping_node", "EUIClippingNode", {
				{"progress_bar", "EUIImage"},
			}},
		}},
		{"UIFXTestNo", "EUINodeBase"},
		{"UIFXTestYes", "EUINodeBase"},
		{"RewardRootBG", "EUIImage", {
			{"RewardRoot", "EUIImage", {
				{"BtnRewardConfirm", "EUIButton"},
				{"LabelRewardMsg", "EUITextLabel"},
				{"ImageReward", "EUIImage"},
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
	{"SceneNodeFish", "EUISceneNode", {
		{"LabelFishTitle", "EUITextLabel"},
	}},
	{"SceneNodeShop", "EUISceneNode", {
		{"LabelShopTitle", "EUITextLabel"},
	}},
}
